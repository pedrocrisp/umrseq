#!/usr/bin/env python3
"""
Assign unique, sample-specific IDs to each interval in a per-sample UMR BED file.

For each input line (chrom, start, end, ...) writes:
    chrom <TAB> start <TAB> end <TAB> <sample_prefix>_UMR_<9-digit counter>

This is step 1 of the UMR consensus pipeline: it runs once per sample (as a SLURM
array task) so that IDs are guaranteed unique across the whole cohort once all
per-sample ".names" files are concatenated in step 2 (21-UMR_consensus_merge.py).

(Named 20-EPIC2_reformat because it reformats per-sample epic2 UMR calls in
preparation for the cohort consensus merge in step 2.)
"""

import sys
import os


def assign_ids(input_bed, output_names, sample_prefix):
    cnt = 1
    with open(input_bed) as infile, open(output_names, "w") as outfile:
        for line in infile:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 3:
                print(f"Warning: skipping malformed line (less than 3 columns): {line.strip()}")
                continue
            uid = f"{sample_prefix}_UMR_{cnt:09d}"
            outfile.write("\t".join(fields[0:3]) + "\t" + uid + "\n")
            cnt += 1
    print(f"Wrote {cnt - 1} UMR(s) with IDs prefixed '{sample_prefix}_UMR_' to {output_names}")


def main():
    if len(sys.argv) != 4:
        print("Usage: python 20-EPIC2_reformat.py <input.bed> <output.names.bed> <sample_prefix>")
        print("\nArguments:")
        print("  input.bed          Per-sample UMR BED file (chrom, start, end, ...)")
        print("  output.names.bed   Output BED file with a unique ID appended as column 4")
        print("  sample_prefix      Sample prefix used to build unique IDs (e.g. TG001)")
        sys.exit(1)

    input_bed, output_names, sample_prefix = sys.argv[1], sys.argv[2], sys.argv[3]

    if not os.path.exists(input_bed):
        print(f"ERROR: Input BED file not found: {input_bed}")
        sys.exit(1)

    assign_ids(input_bed, output_names, sample_prefix)


if __name__ == "__main__":
    main()
