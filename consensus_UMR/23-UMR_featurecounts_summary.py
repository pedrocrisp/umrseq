#!/usr/bin/env python3
"""
Summarise featureCounts read-assignment summary files into one table.

For each sample, reads '<counts_dir>/<sample_prefix>.featurecounts.counts.summary'
(written by featureCounts alongside its counts table) and reports total reads
(sum of every Status row - Assigned plus every Unassigned_* category),
assigned reads, and the percent of reads assigned to a consensus UMR.
"""

import sys
import os


def parse_summary(summary_file):
    assigned = None
    total = 0
    with open(summary_file) as f:
        next(f)  # header line: "Status\t<bam path>"
        for line in f:
            status, count = line.rstrip("\n").split("\t")[0:2]
            count = int(count)
            total += count
            if status == "Assigned":
                assigned = count
    if assigned is None:
        raise ValueError(f"No 'Assigned' row found in {summary_file}")
    return assigned, total


def main():
    if len(sys.argv) != 4:
        print("Usage: python 23-UMR_featurecounts_summary.py <sample_list.txt> <counts_dir> <output_tsv>")
        print("\nArguments:")
        print("  sample_list.txt   Sample prefixes (one per line), same as used for 22-UMR_featurecounts")
        print("  counts_dir        Directory containing '<sample_prefix>.featurecounts.counts.summary' files")
        print("  output_tsv        Output TSV path: sample, total_reads, assigned_reads, percent_assigned")
        sys.exit(1)

    sample_list, counts_dir, output_tsv = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(sample_list) as f:
        sample_prefixes = [line.strip() for line in f if line.strip()]

    with open(output_tsv, "w") as out:
        out.write("sample\ttotal_reads\tassigned_reads\tpercent_assigned\n")
        for sample_prefix in sample_prefixes:
            summary_file = os.path.join(counts_dir, f"{sample_prefix}.featurecounts.counts.summary")
            if not os.path.exists(summary_file):
                print(f"ERROR: Summary file not found: {summary_file}")
                sys.exit(1)

            assigned, total = parse_summary(summary_file)
            percent_assigned = round(100 * assigned / total, 2) if total > 0 else 0.0
            out.write(f"{sample_prefix}\t{total}\t{assigned}\t{percent_assigned}\n")

    print(f"Wrote read support summary for {len(sample_prefixes)} sample(s) to {output_tsv}")


if __name__ == "__main__":
    main()
