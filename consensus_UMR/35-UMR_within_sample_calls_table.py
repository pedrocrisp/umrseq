#!/usr/bin/env python3
"""
Combine every sample's within-sample presence/absence calls into one
UMR x sample table.

Reads each sample's '<sample_prefix>.coverage.calls.tsv' (written by
34-UMR_within_sample_calls.py: chrom, start, end, UMR_ID, depth, YES/NO),
recodes YES/NO as 1/0, and joins them into one table with a UMR_ID column
plus one column per sample - using sample_list.txt directly for both the
sample iteration order and the output column order (fixing a bug in the
original combine_calls.py, which derived each sample's column name by
splitting its calls filename on '.', e.g. yielding 'TG001.regions' instead
of 'TG001').

Some samples may have no calls file (33/34-UMR_within_sample_calls.sh skips
samples whose coverage distribution isn't bimodal) - those samples' columns
are filled with 'NA' for every UMR rather than treated as an error, since a
non-bimodal sample is an expected outcome, not a failure.
"""

import sys
import os


def combine(sample_list_file, calls_dir, output_tsv):
    sample_prefixes = []
    with open(sample_list_file) as fh:
        for line in fh:
            sample_prefix = line.strip()
            if sample_prefix:
                sample_prefixes.append(sample_prefix)

    umr_ids = []
    seen_umr_ids = set()
    calls_by_sample = {}

    for sample_prefix in sample_prefixes:
        calls_file = os.path.join(calls_dir, f"{sample_prefix}.coverage.calls.tsv")
        if not os.path.exists(calls_file):
            print(f"WARNING: No calls file for {sample_prefix} (non-bimodal coverage distribution) - "
                  f"filling with NA: {calls_file}")
            calls_by_sample[sample_prefix] = {}
            continue

        sample_calls = {}
        with open(calls_file) as fh:
            for line in fh:
                fields = line.rstrip("\n").split("\t")
                umr_id, call = fields[3], fields[5]
                sample_calls[umr_id] = "1" if call == "YES" else "0"
                if umr_id not in seen_umr_ids:
                    seen_umr_ids.add(umr_id)
                    umr_ids.append(umr_id)
        calls_by_sample[sample_prefix] = sample_calls

    umr_ids.sort()

    with open(output_tsv, "w") as fh:
        fh.write("UMR_ID\t" + "\t".join(sample_prefixes) + "\n")
        for umr_id in umr_ids:
            row = [calls_by_sample[sample_prefix].get(umr_id, "NA") for sample_prefix in sample_prefixes]
            fh.write(umr_id + "\t" + "\t".join(row) + "\n")

    print(f"Wrote {len(umr_ids)} UMR(s) x {len(sample_prefixes)} sample(s) to {output_tsv}")


def main():
    if len(sys.argv) != 4:
        print("Usage: python 35-UMR_within_sample_calls_table.py <sample_list.txt> <calls_dir> <output_tsv>")
        print("\nArguments:")
        print("  sample_list.txt   Sample prefixes (one per line) - defines column order")
        print("  calls_dir         Directory containing '<sample_prefix>.coverage.calls.tsv' files (step 2's output_dir)")
        print("  output_tsv        Output path for the combined UMR x sample table")
        sys.exit(1)

    sample_list_file, calls_dir, output_tsv = sys.argv[1], sys.argv[2], sys.argv[3]

    if not os.path.exists(sample_list_file):
        print(f"ERROR: Sample list not found: {sample_list_file}")
        sys.exit(1)
    if not os.path.isdir(calls_dir):
        print(f"ERROR: Calls directory not found: {calls_dir}")
        sys.exit(1)

    combine(sample_list_file, calls_dir, output_tsv)


if __name__ == "__main__":
    main()
