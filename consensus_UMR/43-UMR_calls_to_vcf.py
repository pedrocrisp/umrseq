#!/usr/bin/env python3
"""
Convert a UMR presence/absence call table into a placeholder VCF.

Reads a UMR x sample call table with a 'UMR_ID' header column plus one column
per sample - either the across-sample table from step 7
('<out_prefix>.UMR.calls.tsv') or the within-sample table from step 11
('<out_prefix>.UMR.within_sample.calls.tsv') - and writes a VCF to stdout so
UMR calls can be analysed with the same tools as SNPs (e.g. PCA or GWAS
software that reads VCF).

Each UMR becomes one placeholder biallelic site on a dummy chromosome 'chrU'
at consecutive positions (1, 2, 3, ...), with the UMR_ID in the ID column.
Calls are coded as genotypes:

  1  -> 1/1  (UMR present)
  0  -> 0/0  (UMR absent)
  NA -> ./.  (no call - e.g. a sample step 10 couldn't call)

Adapted from make_vcf.py (original author: Agnieszka A. Golicz). Changes:
sample names are taken directly from the table header (the consensus tables
already use the full sample prefixes, so the original's short-ID to name
mapping file isn't needed), NA is written as missing ('./.') rather than
absent ('0/0'), any other value is an error, and a ##contig header line is
added for chrU.
"""

import sys

GENOTYPES = {"1": "1/1", "0": "0/0", "NA": "./."}


def main():
    if len(sys.argv) != 2:
        sys.exit("USAGE: python3 43-UMR_calls_to_vcf.py <UMR_calls_table.tsv> > <output.vcf>")
    calls_table = sys.argv[1]

    with open(calls_table) as fh:
        header = fh.readline().rstrip("\n").split("\t")
        if header[0] != "UMR_ID":
            sys.exit(f"ERROR: expected first header column 'UMR_ID' in {calls_table}, found '{header[0]}'")
        rows = [line.rstrip("\n").split("\t") for line in fh if line.strip()]

    samples = header[1:]

    print("##fileformat=VCFv4.2")
    print(f"##contig=<ID=chrU,length={len(rows)}>")
    print("##ALT=<ID=*,Description=\"Represents allele(s) other than observed.\">")
    print("##INFO=<ID=DP,Number=1,Type=Integer,Description=\"Raw read depth\">")
    print("##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">")
    print("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t" + "\t".join(samples))

    for pos, row in enumerate(rows, start=1):
        if len(row) != len(header):
            sys.exit(f"ERROR: row for {row[0]} has {len(row) - 1} calls, expected {len(samples)}")
        genotypes = []
        for call in row[1:]:
            if call not in GENOTYPES:
                sys.exit(f"ERROR: unexpected call value '{call}' for {row[0]} (expected 1, 0 or NA)")
            genotypes.append(GENOTYPES[call])
        print(f"chrU\t{pos}\t{row[0]}\tA\tT\t10\t.\tDP=5\tGT\t" + "\t".join(genotypes))

    print(f"Converted {len(rows)} UMRs x {len(samples)} samples", file=sys.stderr)


if __name__ == "__main__":
    main()
