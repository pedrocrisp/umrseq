# UMR-seq Core Pipeline

Disclaimer: these pipeline scripts are still in development, provided for use
without warranty.

Version dev v2.0
UMR-seq pipeline dev team

# Updates and version notes

- steps 01-05 (QC, trimming, alignment, coverage tracks, epic2 UMR calls) are
  the core, stable workflow
- `04-bed_tiles` is deprecated (superseded by `03c`), kept for reference
- `09-WGBS_cov_UMR_peaks` is a legacy PBS (`qsub`) script and has not yet been
  ported to SLURM
- `21-` / `21b-` scripts in this folder are older copies of the consensus
  scripts - use the maintained versions in `../consensus_UMR/` (see
  `README_UMR_CONSENSUS.md`)
- module versions are being updated in 2026 (gcc-10/11 builds being phased
  out on Bunya) - check the `module load` lines in each `.sh` script if a job
  fails to start

# Overview

Processes paired-end (or single-end) Illumina UMR-seq reads from raw FASTQ
through to per-sample unmethylated region (UMR) calls, coverage tracks and
differential UMRs:

1. QC and adapter trimming (FastQC, Trim Galore)
2. Alignment and MAPQ filtering (Bowtie2, samtools), with an optional
   duplication rate check (Picard) - not used in the default workflow
3. CPM-normalised coverage tracks and tiles (deepTools `bamCoverage`,
   mosdepth), plus insert size metrics (Picard)
4. Per-sample UMR calling (epic2, with FRiP via deepTools; MACS2 as an
   alternative)
5. Coverage profiles over features of interest (deepTools `computeMatrix`)
6. Differential UMRs between pairs of sample groups (csaw/edgeR)

The per-sample epic2 calls from step 05 are the input to the cohort consensus
and presence/absence calling pipeline in `../consensus_UMR/`.

## Script pattern

Every step is a SLURM array job, one task per sample, split across a pair of
scripts that share a step name:

- `<step>_sbatch.sh` - the submission wrapper you run with `bash`. It reads
  the sample list, works out the array range, creates a timestamped log
  folder (`logs/<YYYYMMDD-HHMMSS>_<step>/`), saves a copy of both scripts
  there for the record, and calls `sbatch`, passing arguments to the job
  script as environment variables via `--export`.
- `<step>.sh` - the job script that runs on the compute node. It `cd`s to the
  submission directory, loads modules / activates the conda environment,
  picks its sample from the sample list using `$SLURM_ARRAY_TASK_ID`, then
  `cd`s into `analysis/` and runs the tool.

Some steps also call an `.R` script from the job script.

`sbatch` stdout/stderr for each array task are written to
`logs/<timestamp>_<step>/<step>_o_<jobID>_<taskID>` and `..._e_...`.

### Arguments common to most steps

- `sample_list.txt` - one sample prefix per line, no file extensions, no
  blank lines (the array size is `wc -l` of this file). To run a single sample a hack is to list this sample, followed by a blank line.
- `walltime` - `HH:MM:SS`
- `memory` - in GB (just the number, e.g. `20`)
- `conda_enviro` - name of the conda environment to activate
- `account_department` - SLURM account string, e.g. `AccountString`

## Project directory layout

Always submit jobs from the project root. Input reads go in `reads/`;
everything else is written under `analysis/` (created automatically).
Because the job scripts `cd analysis` before running, every `bam_dir`,
`reads_folder`, `out_dir` etc. argument is a path **relative to
`analysis/`** (e.g. `trimmed_align_bowtie2`, not
`analysis/trimmed_align_bowtie2`).

```
project/
├── samples.txt
├── reads/                                  # raw <sample>_R1*.fastq.gz / _R2*.fastq.gz
├── logs/                                   # timestamped per-step log folders
└── analysis/
    ├── fastqc_raw/                         # 01-qc
    ├── trimmed/                            # 01-trim_galore_gz
    ├── fastqc/                             # 01-trim_galore_gz (post-trim FastQC)
    ├── trimmed_align_bowtie2/              # 02-bowtie2: <sample>_sorted.bam(.bai)
    ├── trimmed_align_bowtie2_stats/        # 02-bowtie2: flagstat + MAPQ distribution
    ├── trimmed_align_bowtie2_filtered/     # 02b-filter-dups (optional)
    ├── trimmed_align_bowtie2_hacked_bw_deeptools/   # 03c
    ├── trimmed_align_bowtie2_hacked_100bp_tiles/    # 03c
    ├── trimmed_align_bowtie2_hacked_big_tiles/      # 03c
    ├── trimmed_align_bowtie2_mosdepth/              # 03c
    ├── trimmed_align_bowtie2_insert_metrics/        # 03c
    ├── trimmed_align_bowtie2_epic2/                 # 05
    ├── trimmed_align_bowtie2_epic2_FRIP/            # 05
    └── macs2/                                       # macs2 (optional)
```

## Dependencies

Loaded via `module load` on the cluster (Bunya) or from a conda environment
- see the `Modules` block at the top of each `.sh` script.

- FastQC 0.11.9, Trim Galore + cutadapt 4.4 (conda)
- Bowtie2 2.4.5, samtools 1.13
- Picard (jar path set in the scripts / passed as an argument), Java 11+,
  bamtools 2.5.2
- deepTools 3.5.1 and mosdepth (conda) - see "Hacked deepTools" below
- epic2 **0.0.41** (conda) - newer versions' paired-end mode gave ~10x lower
  coverage in testing, so use 0.0.41 in single-end mode
- MACS2 2.2.9.1 (optional)
- R 4.4.2 with `tidyverse`, `ggplot2`, `ggthemes` (step 06) and `csaw`,
  `rtracklayer`, `GenomicRanges`, `edgeR`, `statmod` (step 07)
- bedtools 2.30.0 (step 04 only)

### Hacked deepTools

By default `bamCoverage` merges adjacent bins with the same value into one
bedGraph line. Downstream code that expects fixed-size tiles (e.g. every
100bp tile present) needs this turned off. To build the "hacked" install:

```bash
conda create -n deeptools-hacked python=3.7
conda activate deeptools-hacked
conda install -c bioconda deeptools=3.5.1 mosdepth
```

then in `deeptools/writeBedGraph.py` (e.g.
`~/miniconda3/pkgs/deeptools-3.5.1-pyhdfd78af_1/site-packages/deeptools/`)
uncomment the block marked "uncomment these lines if fixed step bedgraph is
required".

If you only want bigWigs to view in IGV, a normal deepTools install is fine.
If you will use the bedGraph/bigWig outputs to compare coverage between
tiles or samples, use the hacked install with `03c`.

# Usage

## Step 01: QC and trimming

### 01-qc (optional): FastQC on raw reads

```bash
bash 01-qc_sbatch.sh \
    samples.txt \
    1:00:00 \
    5 \
    AccountString
```

Looks for `reads/<sample>*.fastq*`; two files = paired-end. Output in
`analysis/fastqc_raw/` - run `multiqc` there to summarise.

### 01-trim_galore_gz: adapter trimming

```bash
bash 01-trim_galore_gz_sbatch.sh \
    samples.txt \
    20:00:00 \
    20 \
    trimgalore_env \
    AccountString
```

Arguments: `<sample_list> <walltime> <memory> <conda_enviro> <account>`.
Handles paired/single-end and gzipped/uncompressed reads, detected from
`reads/<sample>_R1[_001].fastq[.gz]` / `_R2...`. Trimmed reads go to
`analysis/trimmed/` (`<sample>_R1_val_1.fq.gz`, `<sample>_R2_val_2.fq.gz`)
with post-trim FastQC reports in `analysis/fastqc/`.

### 01b-cat (optional): merge lanes

For libraries sequenced over multiple lanes. Unlike the other steps this is
a single script submitted directly with `sbatch` (it has `#SBATCH` headers
with a hard-coded account - edit before use). It takes a two-column,
whitespace-delimited file: original per-lane name, new merged sample name.

```bash
sbatch --array 1-<n_samples> 01b-cat.sh lane_merge_list.txt
```

Concatenates `analysis/trimmed_lanes/<base>_L*_R{1,2}_val_{1,2}.fq.gz` into
`analysis/trimmed/<new_name>_R{1,2}_val_{1,2}.fq.gz`, writes a new sample
list to `samples_renamed_merged.txt` and renames `samples.txt` to
`samples_old.txt`.

## Step 02: alignment

### 02-bowtie2: align, MAPQ filter, sort, index

```bash
bash 02-bowtie2_sbatch.sh \
    samples.txt \
    trimmed \
    8 \
    ~/refseqs/maize/Zm-B73-v5 \
    10 \
    24:00:00 \
    40 \
    AccountString \
    bai
```

Arguments: `<sample_list> <reads_folder> <bt2_threads> <bt2_genome_index>
<mapq_filter> <walltime> <memory> <account> [genome_index]`.

- `reads_folder` - relative to `analysis/`, usually `trimmed`
- `bt2_genome_index` - Bowtie2 index prefix
- `mapq_filter` - minimum MAPQ to keep; `10` removes multi-mapping reads
  (Bowtie2 gives equally good multi-mappers MAPQ <= 1)
- `genome_index` - optional, `bai` (default) or `csi`. Use `csi` only for
  very large chromosomes (e.g. wheat, barley) when you won't run csaw - csaw
  requires `.bai`, so for large genomes use a split-chromosome reference
  instead (see `../tools/` to recombine outputs afterwards)

Alignment is `--local --very-sensitive-local -X 2000`. Output:
`analysis/<reads_folder>_align_bowtie2/<sample>_sorted.bam` (+ index), and
`<sample>_flagstat.txt` / `<sample>_MAPQ_distribution.txt` in
`<reads_folder>_align_bowtie2_stats/`. Raw and filtered alignment counts are
printed to the job stdout log.

`flagstat_summary.sh` (not a SLURM job - run on an interactive node) makes a
one-row-per-sample table from the sorted BAMs:

```bash
bash flagstat_summary.sh samples.txt analysis/trimmed_align_bowtie2 flagstat > flagstat_summary.tsv
```

### 02b-filter-dups (optional): check duplication rate

Not part of the default workflow - our standard analysis uses the step 02
`<sample>_sorted.bam` files directly and skips this step. Use it to check
the duplication rate of a library and to make a de-duplicated BAM for
comparison.

```bash
bash 02b-filter-dups_sbatch.sh \
    samples.txt \
    trimmed_align_bowtie2 \
    yes \
    ~/software/picard.jar \
    10:00:00 \
    40 \
    AccountString
```

Arguments: `<sample_list> <bam_dir> <paired_end yes|no> <picard_jar>
<walltime> <memory> <account>`. Picard `MarkDuplicates
REMOVE_DUPLICATES=true`, then (PE only) bamtools keeps mapped, properly
paired reads. Outputs in `<bam_dir>_filtered/`:

- `<sample>_NoDupMetrics.txt` - Picard duplication metrics
  (`PERCENT_DUPLICATION` is the duplication rate)
- `<sample>_sorted_NoDup_ProPairs.bam` (+ `.bai`) - de-duplicated BAM

The de-duplicated BAMs are named differently from step 02's
`<sample>_sorted.bam`, so steps 03-07 won't pick them up. `macs2` can use
them with `-f`.

## Step 03: coverage tracks

### 03c-deeptools-hacked_bigWig (recommended)

```bash
bash 03c-deeptools-hacked_bigWig_sbatch.sh \
    samples.txt \
    10:00:00 \
    20 \
    trimmed_align_bowtie2 \
    deeptools-hacked \
    lowres \
    ~/refseqs/maize/maize-fragments-filtered-50%Ns.bed \
    AccountString
```

Arguments (in this order): `<sample_list> <walltime> <memory> <bam_dir>
<conda_enviro> <highres> <blacklist> <account>`.

- `highres` - `highres` to also make a 1bp-resolution bigWig (large files);
  any other value (e.g. `lowres`) skips it
- `blacklist` - BED of regions to exclude, e.g. regions recalcitrant to
  digestion predicted by `../In-silico-digest/`

All tracks are CPM-normalised with `--extendReads` (fills in the whole PE
fragment). Outputs per sample:

| Folder (under `analysis/`) | File | Bin | Blacklist |
|---|---|---|---|
| `<bam_dir>_hacked_bw_deeptools/` | `<sample>.1.bw` (if `highres`) | 1bp | yes |
| `<bam_dir>_hacked_bw_deeptools/` | `<sample>.10.bw` - for IGV and step 06 | 10bp | yes |
| `<bam_dir>_hacked_100bp_tiles/` | `<sample>.bed` (bedGraph, NAs skipped) | 100bp | yes |
| `<bam_dir>_hacked_big_tiles/` | `<sample>_1000bin.bed` | 1kb | no |
| `<bam_dir>_hacked_big_tiles/` | `<sample>_1Mb.bed` | 1Mb | no |
| `<bam_dir>_mosdepth/` | `<sample>.regions.bed.gz` etc. | 500bp | no |
| `<bam_dir>_insert_metrics/` | `<sample>_insert_size_metrics.txt` / `_histogram.pdf` | - | - |

Picard is run from `~/software/picard/build/libs/picard.jar` - edit the path
in `03c-deeptools-hacked_bigWig.sh` if yours is elsewhere.

### 03b-deeptools_bigWig (legacy)

Original version, for a standard deepTools install. Same idea as `03c` but no
blacklist, and writes to `<bam_dir>_bigWigs_deeptools/`,
`<bam_dir>_100bp_tiles/` etc.

```bash
bash 03b-deeptools_bigWig_sbatch.sh samples.txt 10:00:00 20 trimmed_align_bowtie2 deeptools AccountString
```

### 03d-deeptools-hacked_bigTile_beds: CPM tiles at a custom resolution

```bash
bash 03d-deeptools-hacked_bigTile_beds_sbatch.sh \
    samples.txt 4:00:00 20 trimmed_align_bowtie2 deeptools-hacked 5000 none AccountString
```

Arguments are the same as `03c`, except argument 6 is the bin size in bp.
The blacklist argument is required (to keep the same argument order as
`03c`) but not currently used - pass any value, e.g. `none`. Output:
`<bam_dir>_hacked_<res>bp_tiles/<sample>_<res>bp.bed` (bedGraph at `<res>` bp).

### 04-bed_tiles (deprecated)

Earlier bedtools-based 100bp tiling, superseded by `03c` (it doesn't extend
reads to the fragment or handle overlapping mates). Kept for reference.

## Step 05: call UMRs per sample

### 05-epic2 (recommended)

```bash
bash 05-epic2_sbatch.sh \
    samples.txt \
    1:00:00 \
    20 \
    trimmed_align_bowtie2 \
    epic2 \
    ~/refseqs/maize/Zm-B73-v5.chrom.sizes \
    50 \
    ~/refseqs/maize/maize-fragments-filtered-50%Ns.bed \
    AccountString
```

Arguments: `<sample_list> <walltime> <memory> <bam_dir> <conda_enviro>
<chrom_sizes> <bin_size> <blacklist> <account>`. The conda environment needs
epic2 0.0.41 and deepTools.

Calls enriched (unmethylated) regions with epic2 at `bin_size` bp resolution
(`50` gives good UMR resolution), with no background library. Outputs:

- `<bam_dir>_epic2/<sample>.<bin_size>.epic2.bed` - columns `Chromosome Start
  End ChIPCount Score Strand`. `ChIPCount` is the useful coverage metric;
  `Score` isn't meaningful without a background library. This is the input
  to `../consensus_UMR/` step 1 (file suffix `.<bin_size>.epic2.bed`)
- `<bam_dir>_epic2_FRIP/<sample>_FRIP.pdf` and `_FRIP_counts.tab` - fraction
  of reads in the called UMRs (deepTools `plotEnrichment`)

### macs2 (alternative)

Uses flags rather than positional arguments:

```bash
bash macs2_sbatch.sh \
    -i samples.txt \
    -r trimmed_align_bowtie2 \
    -A AccountString \
    -m 20 -c 1 -t 2:00:00 \
    -s 2.1e9 \
    -p yes
```

Required (no defaults - the script exits with an error if any are omitted):
`-i` sample list, `-r` BAM folder, `-A` SLURM account string, and `-s`
effective genome size (e.g. `2.1e9`, or a MACS2 shortcut such as `hs`).

Optional:

- `-p yes|no` paired-end (`-f BAMPE`, default) or single-end
- `-m` memory in GB (default `20`), `-c` CPUs (default `1`), `-t` walltime
  (default `2:00:00`)
- `-C` control sample prefix (optional, default `no` - no control)
- `-B` broad peaks, `-f` use `02b` filtered BAMs, `-D nomodel` to disable
  fragment size modelling (has no effect with `BAMPE`)

Runs with `--keep-dup all`. Output in `analysis/macs2/`.

## Step 06: coverage profile over features

### 06-cov_feature

```bash
bash 06-cov_feature_sbatch.sh \
    samples.txt \
    2:00:00 \
    20 \
    trimmed_align_bowtie2_hacked_bw_deeptools \
    cov_genes \
    ~/refseqs/maize/genes.bed \
    deeptools-hacked \
    AccountString
```

Arguments: `<sample_list> <walltime> <memory> <bigwig_dir> <out_dir>
<feature_bed> <conda_enviro> <account>`. Reads `<bigwig_dir>/<sample>.10.bw`
from `03c` and runs `computeMatrix scale-regions` (features scaled to 1kb,
+/- 2kb flanks), then `plotProfile` and `plotHeatmap`, then
`06-cov_feature_summarise.R` to average each bin across features. Outputs in
`analysis/<out_dir>/`: `<sample>.mat.gz`, `.mat_values.tab`,
`.region_order.bed`, `.mat_metaplot.png`, `.mat_heatmap.png`,
`_mat_values_summarised.tab`, `_mat_metaplot_2.pdf`.

### 06c-cov_feature_heatmap: re-plot with fixed scales

Re-plots the `06` matrices with set axis limits and colour map, so samples
can be compared on the same scale.

```bash
bash 06c-cov_feature_heatmap_sbatch.sh \
    samples.txt 1:00:00 10 cov_genes cov_genes_replot 0 5 RdYlBu deeptools-hacked AccountString
```

Arguments: `<sample_list> <walltime> <memory> <mat_dir> <out_dir> <y_min>
<y_max> <colour_map> <conda_enviro> <account>`.

## Step 07: differential UMRs (csaw)

```bash
bash 07-csaw_sbatch.sh \
    contrasts.txt \
    12:00:00 \
    40 \
    bams_for_csaw/DMR_tests_combos_table.tsv \
    bams_for_csaw \
    ~/refseqs/maize/blacklist.bed \
    3 \
    100 \
    50 \
    AccountString
```

Arguments: `<contrasts_list> <walltime> <memory> <contrasts_table>
<bam_folder> <blacklist> <filter_FC> <window_size> <window_spacing>
<account>`.

One array task per contrast (not per sample). Inputs:

- `contrasts.txt` - one contrast name per line (the `test_name` values)
- `contrasts_table` - TSV with columns `test_name`, `sample1`, `sample2`,
  e.g. `B73_leaf.vs.Mo17_leaf  B73_leaf  Mo17_leaf`
- `bam_folder` - folder of BAMs (with `.bai` index) named
  `<group>.<anything>.bam`, e.g. `B73_leaf.1.bam`, `B73_leaf.2.bam`. Replicates
  are found with the regex `^<group>\..*\.bam$`, so the `.` after the group
  name matters - it stops `RGT` also matching `RGT_callus`
- `filter_FC` - keep windows with at least this fold-enrichment over the
  2kb-bin background (e.g. `3`)
- `window_size` / `window_spacing` - csaw window width and step in bp (e.g.
  `100` / `50`)

Counts reads (MAPQ >= 10, paired-end, fragments <= 500bp, blacklist
excluded) into sliding windows, filters, applies loess normalisation, tests
with edgeR quasi-likelihood F-tests, merges windows within 100bp into regions
(max 5kb), and controls FDR at the region level. Pt/Mt are dropped and
regions with FDR < 0.05 kept. Currently hard-coded for paired-end data.

Outputs in `<bam_folder>_CSAW/<contrast>_FCF<filter_FC>_bin<window_size>_space<window_spacing>/`:

- `<contrast>_differential_UMRs_CSAW_sig_metadata.bed` - significant regions,
  named by the sample group with higher coverage (or `mixed`), score =
  best-window logFC
- `..._sig_metadata_<sample1>.bed` / `_<sample2>.bed` - split by direction
- `..._sig_metadata_less_300bp.bed` / `_greater_300bp.bed` - split by size
- `..._sig_metadata_extend.tsv` - all metadata
- `..._size_summary.csv`, `..._FC_summary.csv`, `..._norm_counts_average.csv`
- QC plots: `window_filter.pdf`, `mds.pdf`, trended bias and BCV plots,
  size histogram, normalised count scatter plots

`07-csaw-gene-overlaps.R` (annotation of DE-UMRs with genes and TEs) is
currently disabled in `07-csaw.sh` because it hard-codes maize annotations.

## Step 09: WGBS methylation over UMRs (legacy PBS)

`09-WGBS_cov_UMR_peaks_sbatch.sh` profiles a reference WGBS dataset (one
bigWig per context: CG, CHG, CHH) over each sample's UMR BED file with
`computeMatrix`. It still uses PBS (`qsub`) and hasn't been ported to SLURM.

## Step 10: FRiP for a custom region set

```bash
bash 10-FRIP_custom_region_sbatch.sh \
    samples.txt \
    2:00:00 \
    20 \
    trimmed_align_bowtie2 \
    deeptools \
    ~/refseqs/maize/blacklist.bed \
    ~/refseqs/maize/WGBS_UMRs.bed \
    WGBS_UMRs \
    AccountString
```

Arguments: `<sample_list> <walltime> <memory> <bam_dir> <conda_enviro>
<blacklist> <region_file> <region_name> <account>`. Fraction of reads in
`region_file` (e.g. UMRs called from WGBS), via deepTools `plotEnrichment`.
Output: `<bam_dir>_FRIP_<region_name>/<sample>_FRIP.pdf` and
`_FRIP_counts.tab`.

## Next steps

To build a cohort consensus UMR set from the step 05 epic2 calls and call
each UMR present/absent per sample, see `../consensus_UMR/README_UMR_CONSENSUS.md`.

# Monitoring and troubleshooting

```bash
squeue --me                                   # job status
ls logs/                                      # one folder per submission
tail logs/<timestamp>_<step>/<step>_e_*_1     # stderr for array task 1
```

- **File not found** - remember `bam_dir`, `reads_folder` etc. are relative
  to `analysis/`, and sample names in `samples.txt` must not include the
  file suffix.
- **R scripts not found** - `06-cov_feature.sh` and `07-csaw.sh` call their
  R scripts from `~/gitrepos/umrseq/UMRseq/`; clone the repo there or edit
  the path.
- **Module not found** - module versions change as the cluster is updated;
  edit the `module load` lines in the `.sh` script.
- **Single sample** - the array range is set to `1` automatically if
  `samples.txt` has only one line.
