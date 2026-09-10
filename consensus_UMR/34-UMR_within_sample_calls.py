#!/usr/bin/env python3
"""
Call each UMR present (YES) or absent (NO) within one sample, based on the
distribution of that sample's mean coverage depth across every UMR.

This is the within-sample counterpart to 25-UMR_calls.py: instead of fitting
one distribution per UMR across many samples (which needs a large, diverse
cohort), it fits one distribution per *sample* across all UMRs - suited to
experiments with only a handful of samples, where there are far more UMRs
than samples to model a distribution over.

For each sample, trims the top 5% of depth values (outliers), fits a KDE to
the remainder, and looks for exactly 3 valleys with 1-2 peaks (bimodal: a
low-coverage "absent" mode and a high-coverage "present" mode). The
present/absent cutoff is the 2nd valley, shifted towards the neighbouring
peak by --shift (default 0.2 - i.e. 20% of the way from the valley to the
peak, rather than sitting exactly on the valley floor). Samples whose depth
distribution isn't bimodal in this sense are skipped (no calls file written)
rather than treated as an error - this is expected for some samples and is
not a failure of the job.

KDE bandwidth is chosen with --bw, either "sj" (Sheather-Jones plug-in via
KDEpy's ISJ implementation - recommended, since it adapts to the data's
actual multimodal structure rather than assuming a unimodal Gaussian
reference, so it's less likely to oversmooth two real coverage populations
into one) or "normal_reference" (statsmodels' default rule-of-thumb).

Writes <sample_prefix>.coverage.calls.tsv (chrom, start, end, UMR_ID, depth,
YES/NO) and <sample_prefix>.coverage.stats.txt (sample, bw method, bw value,
valley count, peak count, bimodal, cutoff - diagnostic, always written) to
output_dir.

Pass --plots <dir> to additionally save a KDE plot and a peak/valley plot for
every sample, including ones skipped for not being bimodal - so a skipped
sample's distribution can still be inspected (the cutoff line is omitted on
those, since there is none).
"""

import sys
import os
import gzip
import argparse

import numpy as np
import statsmodels.api as sm
from findpeaks import findpeaks
from KDEpy import FFTKDE


def call_sample(regions_gz, sample_prefix, output_dir, shift=0.2, bw="sj", plot_dir=None):
    plt = None
    if plot_dir:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

    calls_file = os.path.join(output_dir, f"{sample_prefix}.coverage.calls.tsv")
    stats_file = os.path.join(output_dir, f"{sample_prefix}.coverage.stats.txt")

    rows = []
    with gzip.open(regions_gz, "rt") as fh:
        for line in fh:
            fields = line.rstrip("\n").split("\t")
            rows.append(fields)

    depths = [float(fields[4]) for fields in rows]
    trimmed = sorted(depths)[0:int(0.95 * len(depths))]

    def write_stats(bw_value, valley_count, peak_count, bimodal, cutoff):
        with open(stats_file, "w") as fhs:
            bw_str = f"{bw_value:.6g}" if bw_value is not None else "NA"
            cutoff_str = f"{cutoff:.6g}" if cutoff is not None else "NA"
            fhs.write(f"{sample_prefix}\t{bw}\t{bw_str}\t{valley_count}\t{peak_count}\t"
                      f"{'YES' if bimodal else 'NO'}\t{cutoff_str}\n")

    try:
        # Sheather-Jones (ISJ) bandwidth isn't built into statsmodels, so it's
        # computed via KDEpy and passed in as a fixed numeric bandwidth;
        # "normal_reference" is statsmodels' own built-in rule-of-thumb
        fixed_bw = FFTKDE(kernel="gaussian", bw="ISJ").fit(np.array(trimmed)).bw if bw == "sj" else bw
        kde = sm.nonparametric.KDEUnivariate(np.array(trimmed)).fit(bw=fixed_bw)
        bw_value = kde.bw
    except Exception as exc:
        print(f"Skipping {sample_prefix}: KDE fit failed ({exc})")
        write_stats(None, 0, 0, False, None)
        return False

    x = np.linspace(min(trimmed), max(trimmed), num=1000)
    y = kde.evaluate(x)

    fp = findpeaks(method="peakdetect", lookahead=100)
    results = fp.fit(y)

    peaks = list(results["df"]["peak"])
    valleys = list(results["df"]["valley"])

    valley_idx = [i for i, v in enumerate(valleys) if v]
    peak_idx = [i for i, p in enumerate(peaks) if p]

    bimodal = len(valley_idx) == 3 and len(peak_idx) in (1, 2)

    cutoff = None
    if bimodal:
        if len(peak_idx) == 1:
            shiftb = shift * (peak_idx[0] - valley_idx[1])
        else:
            shiftb = shift * (peak_idx[1] - valley_idx[1])
        cutoff_idx = valley_idx[1] + int(shiftb)
        cutoff = x[cutoff_idx]

    if plot_dir:
        plt.plot(x, y)
        plt.gcf().set_size_inches(7, 3)
        if cutoff is not None:
            plt.axvline(x=cutoff, color="grey", linestyle="-")
        plt.savefig(os.path.join(plot_dir, f"{sample_prefix}.plot1.bi.pdf"))
        plt.clf()
        plt.close()

        fp.plot1d()
        plt.gcf().set_size_inches(7, 3)
        if cutoff is not None:
            plt.axvline(x=cutoff, color="grey", linestyle="-")
        plt.savefig(os.path.join(plot_dir, f"{sample_prefix}.plot2.bi.pdf"))
        plt.clf()
        plt.close()

    if not bimodal:
        print(f"Skipping {sample_prefix}: coverage distribution is not bimodal "
              f"(found {len(valley_idx)} valley(s), {len(peak_idx)} peak(s))")
        write_stats(bw_value, len(valley_idx), len(peak_idx), False, None)
        return False

    write_stats(bw_value, len(valley_idx), len(peak_idx), True, cutoff)

    with open(calls_file, "w") as fh:
        for fields, depth in zip(rows, depths):
            call = "YES" if depth > cutoff else "NO"
            fh.write("\t".join(fields) + "\t" + call + "\n")

    print(f"Called {sample_prefix}: {len(rows)} UMR(s), cutoff={cutoff:.4g}")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("regions_gz", help="mosdepth '<sample>.regions.bed.gz' output from 33-UMR_coverage.sh")
    parser.add_argument("sample_prefix", help="Sample prefix, used to name output files")
    parser.add_argument("output_dir", help="Directory for <sample_prefix>.coverage.calls.tsv and .coverage.stats.txt")
    parser.add_argument("--shift", type=float, default=0.2,
                         help="Fraction of the distance from the 2nd valley to the neighbouring peak to shift "
                              "the present/absent cutoff (default: 0.2)")
    parser.add_argument("--bw", choices=["normal_reference", "sj"], default="sj",
                         help="KDE bandwidth selector: 'sj' (Sheather-Jones plug-in via KDEpy's ISJ - "
                              "recommended, adapts to bimodal/multimodal coverage distributions instead of "
                              "assuming a unimodal Gaussian reference) or 'normal_reference' (statsmodels' "
                              "default rule-of-thumb, which tends to oversmooth multimodal data) (default: sj)")
    parser.add_argument("--plots", metavar="PLOT_DIR", default=None,
                         help="Optional: also save a KDE plot and a peak/valley plot if a bimodal split is found")
    args = parser.parse_args()

    if not os.path.exists(args.regions_gz):
        print(f"ERROR: Regions file not found: {args.regions_gz}")
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)
    if args.plots:
        os.makedirs(args.plots, exist_ok=True)

    call_sample(args.regions_gz, args.sample_prefix, args.output_dir, args.shift, args.bw, args.plots)


if __name__ == "__main__":
    main()
