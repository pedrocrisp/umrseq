# UMR-seq SNP Calling Module

Disclaimer: these pipeline scripts are still in development, provided for use
without warranty.

Version dev v2.0
UMR-seq pipeline dev team

# Acknowledgements

The original SNP calling scripts (`7.call_snps`: `1.call.array.files.slm`,
`2.filter.slm`, `3.merge.sh`, `remove_hets.py`) were developed by Agnieszka
A. Golicz <agnieszka.golicz@agrar.uni-giessen.de>. They have been reformatted
into the same pipeline format as the other UMR-seq modules, so they can be run
on any dataset, but full credit goes to the original developer.

# Overview

Calls SNPs jointly across a cohort of UMR-seq samples from the aligned BAM
files, for example to compare genetic and epigenetic (UMR) variation in the
same samples. Starts after `02b-filter-dups` from the UMRseq pipeline
(`../UMRseq/README_UMRSEQ.md`), using the de-duplicated BAMs.

Three steps, run one after the other:

1. **Per-region SNP calling** - array job, one task per reference sequence.
   Each task runs `bcftools mpileup` + `bcftools call` across **every**
   sample's BAM at once (joint calling), for one region.
2. **Per-region filtering** - array job, one task per region. Keeps
   biallelic SNPs passing missing data and minor allele frequency thresholds.
   Separate from step 1 so you can re-filter with different thresholds
   without repeating the slow calling step.
3. **Merge and het filter** - single job. Concatenates every region into one
   VCF, then removes sites with too many heterozygous calls.

Script trios, run in order:

- `40-SNP_call_sbatch.sh` -> `40-SNP_call.sh` (array job, step 1)
- `41-SNP_filter_sbatch.sh` -> `41-SNP_filter.sh` (array job, step 2)
- `42-SNP_merge_sbatch.sh` -> `42-SNP_merge.sh` -> `42-SNP_remove_hets.py` (single job, step 3)

Each `_sbatch.sh` script checks its inputs, creates a timestamped log folder
(`logs/<YYYYMMDD-HHMMSS>_<step>/`) with a copy of the scripts and input lists,
and submits the job. Run with no arguments to print its usage. All paths are
relative to the directory you submit from (normally the project root, so
UMRseq BAMs are under `analysis/`).

To convert UMR presence/absence calls into the same VCF format, for joint
analysis with these SNPs, see `43-UMR_calls_to_vcf` in
`../consensus_UMR/README_UMR_CONSENSUS.md`.

## Dependencies

- bcftools 1.22, loaded in each job script with
  `module load bcftools/1.22-gcc-14.2.0` (edit the `module load` line if the
  module version changes) - no conda environment needed
- `python3` for step 3 (3.6+, standard library only - whichever `python3` is
  on your `PATH`, e.g. the system `/usr/bin/python3` or your own conda's)
- The reference fasta used for `02-bowtie2`, with a `.fai` index
  (`samtools faidx genome.fa`).
- Indexed BAMs (`.bai` or `.csi`) - `02b-filter-dups` writes `.bai` indexes.

# Usage

## Inputs

- `samples.txt` - one sample prefix per line, same as the UMRseq pipeline.
  These become the sample names in the VCF.
- `regions.txt` - one reference sequence name per line; each becomes one
  array task in steps 1 and 2. To call every sequence in the reference:

  ```bash
  cut -f1 genome.fa.fai > regions.txt
  ```

  For references with many small scaffolds, list only the chromosomes (each
  line is a separate job). Split-chromosome references (e.g. wheat
  `chr1A_part1`, `chr1A_part2`) work as-is, one task per part.

## Step 1: per-region SNP calling (array job)

```bash
bash 40-SNP_call_sbatch.sh \
    samples.txt \
    _sorted_NoDup_ProPairs.bam \
    analysis/trimmed_align_bowtie2_filtered \
    ~/refseqs/wheat/genome.fa \
    regions.txt \
    ./snps_raw \
    24:00:00 \
    20 \
    AccountString
```

Arguments: `<sample_list> <bam_suffix> <bam_dir> <reference_fasta>
<regions_list> <output_dir> <walltime> <memory> <account>`.

BAMs are matched as `<bam_dir>/<sample_prefix>*<bam_suffix>`. Before
submitting, the runner checks that every sample matches exactly one BAM with
an index, then writes `bam_list.txt` and `sample_names.txt` (same order) to
`output_dir`, so a missing BAM fails straight away rather than in every task.

Calling settings (fixed in `40-SNP_call.sh`, same as the original):

- `bcftools mpileup --skip-indels --min-MQ 10 -a FORMAT/AD,FORMAT/DP` - SNPs
  only, MAPQ >= 10 (matches the `02-bowtie2` filter), and per-sample allele
  depth (AD) and read depth (DP) recorded for downstream depth filtering
- `bcftools call --ploidy 2 -mv` - diploid multiallelic caller, variant sites
  only. For polyploids where subgenomes are separate chromosomes (e.g. wheat)
  each subgenome is called as diploid

The UMRseq BAMs have no read groups, so mpileup would name each sample by its
BAM path - the VCF is renamed to the sample prefixes with `bcftools reheader`.

Walltime depends on region size and number of samples; joint calling a large
chromosome across hundreds of samples can take many hours - test with a few
regions first.

Wait for every array task to finish successfully (`squeue --me`), then:

## Step 2: per-region filtering (array job)

```bash
bash 41-SNP_filter_sbatch.sh \
    regions.txt \
    ./snps_raw \
    ./snps_filtered \
    0.1 \
    0.05 \
    2:00:00 \
    8 \
    AccountString
```

Arguments: `<regions_list> <input_dir> <output_dir> <max_missing> <min_maf>
<walltime> <memory> <account>`.

- `max_missing` - remove sites where more than this fraction of samples have
  a missing genotype (`0.1` = keep sites called in at least 90% of samples)
- `min_maf` - minimum minor allele frequency (`0.05`)

`0.1` and `0.05` are the original pipeline's values; adjust for your dataset
(e.g. relax `max_missing` for low-coverage samples, or raise `min_maf` for a
small cohort). Also keeps biallelic SNPs only (`-m2 -M2 -v snps`).

To compare thresholds, re-run with a different `output_dir` - step 1 doesn't
need repeating.

## Step 3: merge regions and remove het sites (single job)

```bash
bash 42-SNP_merge_sbatch.sh \
    regions.txt \
    ./snps_filtered \
    ./snps_merged \
    all_samples \
    0.1 \
    0.05 \
    0.05 \
    4:00:00 \
    8 \
    AccountString
```

Arguments: `<regions_list> <input_dir> <output_dir> <out_prefix>
<max_het_frac> <min_hom_alt_frac> <min_hom_ref_frac> <walltime> <memory>
<account>`.

Concatenates every region's filtered VCF in `regions.txt` order, then runs
`42-SNP_remove_hets.py`, which keeps only sites where:

1. homozygous-alt (`1/1`) calls outnumber heterozygous (`0/1`) calls,
2. het calls are below `max_het_frac` of samples (suggested `0.1`),
3. hom-alt calls are above `min_hom_alt_frac` of samples (suggested `0.05`), and
4. hom-ref (`0/0`) calls are above `min_hom_ref_frac` of samples (suggested `0.05`).

Fractions are of all samples, including missing genotypes. This is aimed at
mostly-homozygous (inbred) material, where het calls at a site usually mean
mis-mapping between paralogues or subgenomes rather than true
heterozygosity. The suggested thresholds are the original `remove_hets.py`
values; adjust them for your material (e.g. raise `max_het_frac` for
outcrossing species).

# Outputs

**Step 1** (in step 1's `output_dir`):

- `bam_list.txt`, `sample_names.txt` - BAMs used and their VCF sample names
- `<region>.raw.vcf.gz` (+ `.csi`) - all variant sites called in that region

**Step 2** (in step 2's `output_dir`): `<region>.filtered.vcf.gz` (+ `.csi`)
- biallelic SNPs passing the missing data and MAF filters. Site counts before
and after filtering are printed to the job stdout log.

**Step 3** (in step 3's `output_dir`):

- `<out_prefix>.snps.vcf.gz` (+ `.csi`) - all regions' filtered SNPs combined
- `<out_prefix>.snps.nohet.vcf.gz` (+ `.csi`) - after the het filter; this is
  the final SNP set
- `<out_prefix>.filtered_vcf_list.txt` - the region VCFs merged, in order

SNP counts for both VCFs are printed to the job stdout log, and the het
filter's kept/removed counts to the stderr log.

# Changes from the original scripts

- Inputs (BAMs, reference, regions, sample names) are arguments instead of
  hard-coded paths and dataset-specific list files.
- Regions are passed to mpileup with `-r <sequence>`, so the per-region BED
  files (`make_bed.py`, `Wheat.chrs`) are no longer needed.
- Sample names are set with `bcftools reheader` from `samples.txt`, instead
  of stripping BAM paths and suffixes with `sed`.
- mpileup also records `FORMAT/AD,FORMAT/DP` (new - the calls themselves are
  unchanged).
- The missing data and MAF thresholds are arguments to step 2.
- Regions are merged in `regions.txt` order (the original used `ls` order,
  which can differ from the reference sequence order that `bcftools concat`
  expects).
- All outputs are bgzipped and indexed.
