#!/usr/bin/env python3
"""
Split a UMR x sample CPM matrix into batches of UMR rows (round robin),
so that the per-UMR distribution modelling in 25-UMR_calls.py can run as a
SLURM array job (one task per batch) instead of one long serial job.

Writes batch0.tsv, batch1.tsv, ... (each with the header line plus its
share of UMR rows) to output_dir, and a batch_list.txt manifest of their
paths - consumed by 25-UMR_calls_sbatch.sh the same way a sample list
drives the other array jobs in this pipeline.
"""

import sys
import os
import math


def main():
    if len(sys.argv) != 4:
        print("Usage: python 24-UMR_combine_calls_split.py <cpm.tsv> <output_dir> <batch_size>")
        print("\nArguments:")
        print("  cpm.tsv      UMR x sample CPM matrix (header + one row per UMR)")
        print("  output_dir   Directory for batch0.tsv, batch1.tsv, ... and batch_list.txt")
        print("  batch_size   Target number of UMRs per batch")
        sys.exit(1)

    cpm_tsv, output_dir, batch_size = sys.argv[1], sys.argv[2], int(sys.argv[3])
    os.makedirs(output_dir, exist_ok=True)

    with open(cpm_tsv) as f:
        header = f.readline()
        data_lines = f.readlines()

    num_batches = max(1, math.ceil(len(data_lines) / batch_size))
    print(f"{len(data_lines)} UMR(s), target {batch_size}/batch -> {num_batches} batch(es)")

    batch_paths = [os.path.join(output_dir, f"batch{i}.tsv") for i in range(num_batches)]
    handles = [open(p, "w") for p in batch_paths]
    try:
        for h in handles:
            h.write(header)
        for i, line in enumerate(data_lines):
            handles[i % num_batches].write(line)
    finally:
        for h in handles:
            h.close()

    batch_list = os.path.join(output_dir, "batch_list.txt")
    with open(batch_list, "w") as f:
        for p in batch_paths:
            f.write(p + "\n")

    print(f"Wrote {num_batches} batch file(s) and {batch_list}")


if __name__ == "__main__":
    main()
