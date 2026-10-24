#!/usr/bin/env python3
"""
Remove SNP sites with too many heterozygous calls.

Reads a VCF (a file path, or '-' for stdin) and writes to stdout only the
sites where, counting each sample's genotype (GT, first FORMAT field):

  1. homozygous-alt (1/1) calls outnumber heterozygous (0/1) calls,
  2. heterozygous calls are below --max-het-frac of all samples,
  3. homozygous-alt calls are above --min-hom-alt-frac of all samples, and
  4. homozygous-ref (0/0) calls are above --min-hom-ref-frac of all samples.

Fractions are of all samples, including missing (./.) genotypes. Header
lines are passed through unchanged. Kept/removed counts go to stderr.

Adapted from remove_hets.py (original author: Agnieszka A. Golicz) - same
logic and default thresholds, with the thresholds exposed as flags.
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("vcf", help="Input VCF (uncompressed), or '-' for stdin")
    parser.add_argument("--max-het-frac", type=float, default=0.1)
    parser.add_argument("--min-hom-alt-frac", type=float, default=0.05)
    parser.add_argument("--min-hom-ref-frac", type=float, default=0.05)
    args = parser.parse_args()

    fh = sys.stdin if args.vcf == "-" else open(args.vcf)

    kept = 0
    removed = 0
    for line in fh:
        if line.startswith("#"):
            sys.stdout.write(line)
            continue
        fields = line.rstrip("\n").split("\t")
        het = 0
        hom_alt = 0
        hom_ref = 0
        total = 0
        for sample_field in fields[9:]:
            gt = sample_field.split(":")[0]
            if gt == "0/1":
                het += 1
            elif gt == "1/1":
                hom_alt += 1
            elif gt == "0/0":
                hom_ref += 1
            total += 1
        if (hom_alt > het
                and het / total < args.max_het_frac
                and hom_alt / total > args.min_hom_alt_frac
                and hom_ref / total > args.min_hom_ref_frac):
            sys.stdout.write(line)
            kept += 1
        else:
            removed += 1

    print(f"Het filter: kept {kept} sites, removed {removed} sites", file=sys.stderr)


if __name__ == "__main__":
    main()
