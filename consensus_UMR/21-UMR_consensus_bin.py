#!/usr/bin/env python3
"""
Split each interval in a consensus UMR BED file into consecutive,
non-overlapping bins of a fixed size.

If an interval's length isn't an exact multiple of bin_size, the leftover
base pairs are trimmed evenly from both ends (the shorter side gets any odd
extra bp) before binning, so every bin is exactly bin_size long. Intervals
shorter than bin_size are retained as a single untrimmed bin named
'<parent_id>.0' instead of being split (counted and reported, not an error).

Each bin is named '<parent_id>.<n>' (1-based), where parent_id is column 4
of the input BED. Output is BED4 (chrom, start, end, bin_id); any columns
beyond the first four are ignored.

Usage:
    python 21-UMR_consensus_bin.py <input.bed> <output.bed> <bin_size>
"""

import sys
import argparse


def bin_regions(input_bed, output_bed, bin_size):
    written = 0
    skipped = 0
    with open(input_bed) as in_fh, open(output_bed, "w") as out_fh:
        for line in in_fh:
            chrom, start, end, parent_id = line.rstrip("\n").split("\t")[0:4]
            start, end = int(start), int(end)

            remainder = (end - start) % bin_size
            n_bins = (end - start - remainder) // bin_size
            if n_bins == 0:
                out_fh.write(f"{chrom}\t{start}\t{end}\t{parent_id}.0\n")
                skipped += 1
                written += 1
                continue

            trim_left = remainder // 2
            region_start = start + trim_left

            for i in range(n_bins):
                bin_start = region_start + i * bin_size
                bin_end = bin_start + bin_size
                out_fh.write(f"{chrom}\t{bin_start}\t{bin_end}\t{parent_id}.{i + 1}\n")
                written += 1

    print(f"Wrote {written} bin(s) of {bin_size}bp from {input_bed}; "
          f"{skipped} region(s) shorter than {bin_size}bp were retained untrimmed as '<id>.0'",
          file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_bed", help="Consensus UMR BED (chrom, start, end, id, ...)")
    parser.add_argument("output_bed", help="Output path for the binned BED4 file")
    parser.add_argument("bin_size", type=int, help="Bin size in bp (e.g. 50)")
    args = parser.parse_args()

    if args.bin_size < 1:
        print(f"ERROR: bin_size must be >= 1 (got {args.bin_size})", file=sys.stderr)
        sys.exit(1)

    bin_regions(args.input_bed, args.output_bed, args.bin_size)


if __name__ == "__main__":
    main()
