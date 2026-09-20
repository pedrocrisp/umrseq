#!/usr/bin/env python3
"""
Call each UMR in a batch as present (YES) or absent (NO) in each sample,
based on the distribution of that UMR's CPM values across samples.

For each UMR, fits a KDE to the (bottom 98% of) per-sample CPM values, finds
peaks/valleys in the density, and - if the distribution looks bimodal - uses
the valley between the two modes as a present/absent cutoff. UMRs without a
clear bimodal split, or where fewer than 5% of samples fall on either side of
the cutoff, are dropped (no call).

Writes <batch_id>.calls (UMR_ID + YES/NO per sample, same sample columns as
the input) and <batch_id>.UMR.stats.txt (UMR_ID, valley count, peak count -
diagnostic) to output_dir, where batch_id is the input filename without its
extension.

Pass --plots <dir> to additionally save a KDE plot and a peak/valley plot
for every called UMR to <dir> - useful for spot-checking the cutoffs on a
small subset of UMRs (see 27-UMR_calls_qc_plots.sh), too slow to do for
every UMR in a full run.
"""

import sys
import os
import argparse

import numpy as np
import statsmodels.api as sm
from findpeaks import findpeaks


def call_batch(batch_tsv, output_dir, plot_dir=None):
    plt = None
    if plot_dir:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

    batch_id = os.path.splitext(os.path.basename(batch_tsv))[0]
    calls_file = os.path.join(output_dir, f"{batch_id}.calls")
    stats_file = os.path.join(output_dir, f"{batch_id}.UMR.stats.txt")

    called_count = 0
    with open(calls_file, "w") as fh, open(stats_file, "w") as fhs:
        for line in open(batch_tsv):
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "UMR_ID":
                fh.write("\t".join(fields) + "\n")
                continue

            umr_id = fields[0]
            counts = [float(n) for n in fields[1:]]
            trimmed = sorted(counts)[0:int(0.98 * len(counts))]

            try:
                kde = sm.nonparametric.KDEUnivariate(np.array(trimmed)).fit()
            except Exception:
                continue

            x = np.linspace(min(trimmed), max(trimmed), num=1000)
            y = kde.evaluate(x)

            fp = findpeaks(method="peakdetect", lookahead=50)
            results = fp.fit(y)

            peaks = list(results["df"]["peak"])
            valleys = list(results["df"]["valley"])
            ys = list(results["df"]["y"])

            valley_idx = [i for i, v in enumerate(valleys) if v]
            peak_idx = [i for i, p in enumerate(peaks) if p]

            fhs.write(f"{umr_id}\t{len(valley_idx)}\t{len(peak_idx)}\n")

            # Need to decide what to do when there are more than two peaks
            if len(valley_idx) == 3 and len(peak_idx) in (1, 2):
                cutoff_idx = valley_idx[1]
                cutoff = x[cutoff_idx]
            elif len(valley_idx) > 3:
                split_valley = valley_idx[2]
                before = [ys[p] for p in peak_idx if p < split_valley]
                after = [ys[p] for p in peak_idx if p >= split_valley]
                try:
                    if max(after) < min(before):
                        cutoff_idx = valley_idx[1]
                        cutoff = x[cutoff_idx]
                    else:
                        continue
                except ValueError:
                    continue
            else:
                continue

            calls = ["YES" if c > cutoff else "NO" for c in counts]
            yes_count = calls.count("YES")
            no_count = calls.count("NO")

            if yes_count > 0.05 * len(counts) and no_count > 0.05 * len(counts):
                fh.write(umr_id + "\t" + "\t".join(calls) + "\n")
                called_count += 1

                if plot_dir:
                    plt.plot(x, y)
                    plt.gcf().set_size_inches(7, 3)
                    plt.savefig(os.path.join(plot_dir, f"{umr_id}.plot1.bi.png"))
                    plt.clf()
                    plt.close()

                    fp.plot1d()
                    plt.gcf().set_size_inches(7, 3)
                    plt.axvline(x=cutoff, color="grey", linestyle="-")
                    plt.savefig(os.path.join(plot_dir, f"{umr_id}.plot2.bi.png"))
                    plt.clf()
                    plt.close()

    print(f"Called {called_count} UMR(s); wrote {calls_file} and {stats_file}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("batch_tsv", help="Batch CPM matrix: UMR_ID column + one CPM column per sample")
    parser.add_argument("output_dir", help="Directory for <batch_id>.calls and <batch_id>.UMR.stats.txt")
    parser.add_argument("--plots", metavar="PLOT_DIR", default=None,
                         help="Optional: also save a KDE plot and a peak/valley plot for every called UMR here")
    args = parser.parse_args()

    if not os.path.exists(args.batch_tsv):
        print(f"ERROR: Batch file not found: {args.batch_tsv}")
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)
    if args.plots:
        os.makedirs(args.plots, exist_ok=True)

    call_batch(args.batch_tsv, args.output_dir, args.plots)


if __name__ == "__main__":
    main()
