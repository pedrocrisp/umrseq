#!/usr/bin/env python3
"""
Build cohort consensus UMRs from per-sample UMRs that have been merged with
bedtools (bedtools merge -c 4 -o collapse -delim "|").

For each merged interval, the individual per-sample UMRs that were collapsed
into it are split out, outliers more than `length_multiplier` times the median
UMR length are dropped, and the median start/end of the remaining UMRs is
reported as the consensus interval. If the median interval spans less than
`ratio_threshold` of the full (min-start to max-end) interval, both the full
interval (CON_UMR) and the tighter median interval (ALT_CON_UMR) are reported;
otherwise only the median interval is reported as CON_UMR.

Usage:
    python 21-UMR_consensus_merge.py <all_umr.bed> <all_umr.merged.bed> \
        [--length-multiplier 10] [--ratio-threshold 0.5]
"""

import sys
import argparse
import statistics


def load_umr_lengths(all_umr_bed):
    starts, ends, lengths = {}, {}, {}
    for line in open(all_umr_bed):
        chrom, start, end, uid = line.rstrip("\n").split("\t")[0:4]
        starts[uid] = int(start)
        ends[uid] = int(end)
        lengths[uid] = int(end) - int(start)
    return starts, ends, lengths


def build_consensus(all_umr_bed, merged_bed, length_multiplier, ratio_threshold, out=sys.stdout):
    starts, ends, lengths = load_umr_lengths(all_umr_bed)

    cnt = 1
    for line in open(merged_bed):
        fields = line.rstrip("\n").split("\t")
        chrom, member_ids = fields[0], fields[3].split("|")

        member_lengths = [lengths[uid] for uid in member_ids]
        median_length = statistics.median(member_lengths)

        kept_ids = [uid for uid in member_ids if lengths[uid] < length_multiplier * median_length]
        dropped_ids = list(set(member_ids) - set(kept_ids))

        kept_starts = [starts[uid] for uid in kept_ids]
        kept_ends = [ends[uid] for uid in kept_ids]

        consensus_start = int(statistics.median(kept_starts))
        consensus_end = int(statistics.median(kept_ends))
        max_start = sorted(kept_starts)[0]
        max_end = sorted(kept_ends)[-1]

        consensus_id = f"CON_UMR_{cnt:09d}"
        kept_str = "|".join(kept_ids)
        dropped_str = "|".join(dropped_ids)

        if (consensus_end - consensus_start) / (max_end - max_start) < ratio_threshold:
            out.write(f"{chrom}\t{max_start}\t{max_end}\t{consensus_id}\t{kept_str}\t{dropped_str}\n")
            alt_id = f"ALT_CON_UMR_{cnt:09d}"
            out.write(f"{chrom}\t{consensus_start}\t{consensus_end}\t{alt_id}\t{kept_str}\t{dropped_str}\n")
        else:
            out.write(f"{chrom}\t{consensus_start}\t{consensus_end}\t{consensus_id}\t{kept_str}\t{dropped_str}\n")

        cnt += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("all_umr_bed", help="Concatenated, sorted, per-UMR BED file (all.umr.bed)")
    parser.add_argument("merged_bed", help="bedtools merge output with collapsed IDs in column 4")
    parser.add_argument("--length-multiplier", type=float, default=10,
                         help="Drop member UMRs longer than this multiple of the median member length (default: 10)")
    parser.add_argument("--ratio-threshold", type=float, default=0.5,
                         help="If median-interval/max-interval length ratio is below this, report both CON_UMR and ALT_CON_UMR (default: 0.5)")
    args = parser.parse_args()

    build_consensus(args.all_umr_bed, args.merged_bed, args.length_multiplier, args.ratio_threshold)


if __name__ == "__main__":
    main()
