# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bioinformatics pipeline scripts for plant genomics and epigenetics. The main functionality is chromosome recombination - converting genomic files with split chromosomes (e.g., chr1H0, chr1H1) back to full chromosomes (chr1H) for barley (Morex pseudomolecules).

## Architecture

All pipelines follow a two-tier SLURM job submission pattern:

```
*_sbatch.sh (orchestrator) → sbatch --array → *.sh (job script) → *.py (processing logic)
```

### Script Trios

**BigWig Recombination:**
- `recombine_bigwig_sbatch.sh` - Submission wrapper (validates inputs, submits array job)
- `recombine_bigwig.sh` - SLURM job script (runs per sample)
- `recombine_bigwig.py` - Core logic (bigWig → bedGraph → transform → bigWig)

**BED Recombination:**
- `recombine_bed_sbatch.sh` - Submission wrapper
- `recombine_bed.sh` - SLURM job script
- `recombine_bed.py` - Core logic (pure Python coordinate transformation)

**Legacy QC/Trimming:**
- `01-qc_sbatch.sh` / `01-qc.sh` - FastQC quality control
- `01-trim_galore_swift_sbatch.sh` / `01-trim_galore_swift.sh` - Adapter trimming

**UMR Consensus (six trios + two optional trios - see README_UMR_CONSENSUS.md):**
- `20-EPIC2_reformat_sbatch.sh` / `20-EPIC2_reformat.sh` / `20-EPIC2_reformat.py` - Phase 1, array job: assigns a unique ID to every UMR in every sample
- `21-UMR_consensus_merge_sbatch.sh` / `21-UMR_consensus_merge.sh` / `21-UMR_consensus_merge.py` + `21-UMR_consensus_bin.py` - Phase 2, single job (run manually after phase 1 completes for all samples): concatenates, `bedtools merge`s, and collapses overlapping per-sample UMRs into cohort consensus UMRs, converts the consensus to SAF format, then splits every consensus UMR into consecutive `bin_size`bp sub-bins (named `<parent_id>.<n>`, trimming leftover bp evenly from both ends) and writes binned BED/SAF equivalents
- `21b-UMR_consensus_merge_background_sbatch.sh` / `21b-UMR_consensus_merge_background.sh` - Optional add-on to phase 2, single job, run any time after phase 2: `bedtools shuffle`s a random subsample of a given consensus BED (phase 2's whole-UMR or binned output) to non-UMR-overlapping genomic locations to build a background/noise BED+SAF (IDs prefixed `BG_`), and a combined UMR+background BED+SAF for use as step 9's `consensus_bed` - output files are named after the input consensus BED's basename, not a separate prefix (no `.py` - pure bash/awk/bedtools)
- `22-UMR_featurecounts_sbatch.sh` / `22-UMR_featurecounts.sh` - Phase 3, array job (run manually after phase 2 completes): runs `featureCounts` per sample against the phase 2 SAF annotation to count read support for each consensus UMR (no `.py` - calls `featureCounts` directly, like `01-qc.sh` calls `fastqc` directly)
- `23-UMR_featurecounts_summary_sbatch.sh` / `23-UMR_featurecounts_summary.sh` / `23-UMR_featurecounts_summary.py` - Phase 4, single job (run manually after phase 3 completes for all samples): parses every sample's `featureCounts` `.summary` file (not the stdout log) into one table of total/assigned reads and percent assigned
- `24-UMR_combine_calls_sbatch.sh` / `24-UMR_combine_calls.sh` / `24-UMR_combine_calls_cpm.R` + `24-UMR_combine_calls_split.py` - Phase 5, single job (run manually after phase 3 completes for all samples): builds a UMR x sample counts matrix, CPM-normalises it (edgeR), and splits it into batches of UMRs for phase 6
- `25-UMR_calls_sbatch.sh` / `25-UMR_calls.sh` / `25-UMR_calls.py` - Phase 6, array job (run manually after phase 5 completes), one task per *batch of UMRs* (not per sample): fits a KDE per UMR across samples, calls present/absent against a bimodal valley cutoff when one exists
- `26-UMR_calls_table_sbatch.sh` / `26-UMR_calls_table.sh` - Phase 7, single job (run manually after phase 6 completes for all batches): aggregates every batch's calls into one table (no `.py` - pure bash)
- `27-UMR_calls_qc_plots_sbatch.sh` / `27-UMR_calls_qc_plots.sh` - Optional phase 8, single job, run any time after phase 7: reuses `25-UMR_calls.py --plots` on a random subset of called UMRs to save diagnostic KDE/peak plots
- Supersedes `2.consensus.pe/`, `3.calculate_support.pe.fc/`, and `5.across_samples.pe.v2/`, which hardcoded a working directory and used manually maintained sample-to-ID/sample-to-BAM mapping files (`list1.txt`, `list.f.txt`, `list.n.txt`) instead of a sample list

**UMR Within-Sample Calling (three more trios - alternative to phases 5-7, for cohorts too small to model a per-locus distribution across samples - see README_UMR_CONSENSUS.md):**
- `33-UMR_coverage_sbatch.sh` / `33-UMR_coverage.sh` - Phase 9, array job (run manually after phase 2 completes): runs `mosdepth` per sample against phase 2's consensus BED to get mean read depth per UMR (no `.py` - calls `mosdepth` directly)
- `34-UMR_within_sample_calls_sbatch.sh` / `34-UMR_within_sample_calls.sh` / `34-UMR_within_sample_calls.py` - Phase 10, array job (run manually after phase 9 completes), one task per *sample* (not per UMR): fits a KDE (bandwidth selectable via `--bw`, `sj`/Sheather-Jones recommended or `normal_reference`) per sample across UMRs, calls present/absent against a shifted bimodal valley cutoff when one exists; samples without a bimodal split are skipped (warning, not a failure)
- `35-UMR_within_sample_calls_table_sbatch.sh` / `35-UMR_within_sample_calls_table.sh` / `35-UMR_within_sample_calls_table.py` - Phase 11, single job (run manually after phase 10 completes for all samples): joins every sample's calls into one UMR x sample table, filling `NA` for samples phase 10 couldn't call
- Supersedes `3.calculate_support.pe.md/` and `4.within_samples.pe/`, which hardcoded a working directory, used manually maintained sample-to-ID mapping files (`list.txt`, `list2.txt`), derived sample names by splitting filenames on `.` (producing `"TG001.regions"` instead of `"TG001"`), destructively `gunzip`-ed mosdepth's only compressed output in place, and crashed with an unhandled `NameError` on any sample whose coverage distribution wasn't bimodal

### Key Patterns

1. **Sample list-driven**: Jobs read sample prefixes from a text file (one per line)
2. **SLURM array jobs**: Parallel processing via `SLURM_ARRAY_TASK_ID` (one task per sample). Steps that need every sample's output at once, like the UMR consensus merge phase, run as a single non-array job instead, submitted manually after the array job completes
3. **Timestamped logging**: All runs create `logs/YYYYMMDD-HHMMSS_<step>/` directories
4. **Conda environments**: Passed via `conda_enviro` argument and activated in job scripts
5. **Script directory resolution**: Job scripts call Python scripts via a hardcoded path (`~/gitrepos/AI_code_dev_testing/<script>.py`), not a dynamically resolved `SCRIPT_DIR` - this is intentional (see git history), keep this convention for new job scripts

## Common Commands

### Submit BigWig recombination job
```bash
bash recombine_bigwig_sbatch.sh samples.txt _MAPQ10.bw conversion_table.csv ./bigwigs ./bigwigs_combined 12:00:00 8 myenv my_department
```

### Submit BED recombination job
```bash
bash recombine_bed_sbatch.sh samples.txt .bed conversion_table.csv ./beds ./beds_combined 4:00:00 4 myenv my_department
```

### Build UMR cohort consensus, read support, and presence/absence calls (7 steps - each only after the previous step's array/job finishes for every sample/batch)
```bash
bash 20-EPIC2_reformat_sbatch.sh samples.txt .UMR.epic2.bed ./umr_calls ./umr_names 1:00:00 2 myenv my_department
bash 21-UMR_consensus_merge_sbatch.sh samples.txt .UMR.epic2.bed ./umr_names ./umr_consensus all_samples 50 4:00:00 8 myenv my_department
bash 22-UMR_featurecounts_sbatch.sh samples.txt .pe.rd.bam ./umr_consensus/all_samples.umr.merged.consensus.noALT.saf ./bams ./umr_counts 4:00:00 8 myenv my_department
bash 23-UMR_featurecounts_summary_sbatch.sh samples.txt ./umr_counts ./umr_counts all_samples 0:30:00 2 myenv my_department
bash 24-UMR_combine_calls_sbatch.sh samples.txt ./umr_counts ./umr_calling all_samples 1000 3:00:00 20 myenv my_department
bash 25-UMR_calls_sbatch.sh ./umr_calling/batches/batch_list.txt ./umr_calling/calls 2:00:00 30 myenv my_department
bash 26-UMR_calls_table_sbatch.sh ./umr_calling/batches/batch_list.txt samples.txt ./umr_calling/calls ./umr_calling all_samples 0:30:00 4 my_department
```

### Build UMR within-sample presence/absence calls (alternative to steps 5-7 above, for small cohorts - run steps 1-2 first, then these 3 steps)
```bash
bash 33-UMR_coverage_sbatch.sh samples.txt .pe.rd.bam ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed ./bams ./umr_coverage 4:00:00 8 myenv my_department
bash 34-UMR_within_sample_calls_sbatch.sh samples.txt ./umr_coverage ./umr_within_sample_calls 0.2 sj 1:00:00 4 myenv my_department
bash 35-UMR_within_sample_calls_table_sbatch.sh samples.txt ./umr_within_sample_calls ./umr_within_sample_calls all_samples 0:30:00 2 myenv my_department
```

### Add background/noise regions for the within-sample workflow (optional, run after step 2, before step 9)
```bash
bash 21b-UMR_consensus_merge_background_sbatch.sh ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed genome.fa.fai ./umr_consensus 1.0 42 1:00:00 4 myenv my_department
# then use ./umr_consensus/all_samples.umr.merged.consensus.noALT.umr_plus_background.bed as step 9's consensus_bed instead of the plain consensus BED
bash 33-UMR_coverage_sbatch.sh samples.txt .pe.rd.bam ./umr_consensus/all_samples.umr.merged.consensus.noALT.umr_plus_background.bed ./bams ./umr_coverage 4:00:00 8 myenv my_department
```

### Monitor jobs
```bash
squeue -u $USER
tail logs/*/recombine_*_o_*_1
```

## Arguments Order (sbatch scripts)

**recombine_bigwig_sbatch.sh / recombine_bed_sbatch.sh / 20-EPIC2_reformat_sbatch.sh:**
1. sample_list.txt
2. file_suffix
3. conversion_table.csv (recombine only - UMR consensus has no conversion table)
4. input_dir
5. output_dir
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro
9. account_department

**21-UMR_consensus_merge_sbatch.sh** (single job, not array - run after step 1's array job finishes for all samples):
1. sample_list.txt (same file used for step 1)
2. file_suffix (same suffix used for step 1)
3. names_dir (step 1's output_dir)
4. output_dir
5. out_prefix (used to name cohort output files)
6. bin_size (bp size of the consecutive sub-bins each consensus UMR is split into, e.g. 50 - leftover bp are trimmed evenly from both ends; UMRs shorter than bin_size are retained untrimmed as a single `<parent_id>.0` bin instead of being split)
7. walltime (HH:MM:SS)
8. memory (GB)
9. conda_enviro
10. account_department

**21b-UMR_consensus_merge_background_sbatch.sh** (single job, not array - optional, run any time after step 2):
1. consensus_bed (step 2's consensus BED to base the background lengths on, e.g. `<out_prefix>.umr.merged.consensus.noALT.bed`, or the binned `<out_prefix>.umr.merged.consensus.noALT.<bin_size>.bed` if background regions should match bin lengths instead - output files are named after this input file's basename)
2. genome_file (tab-delimited chrom sizes, e.g. a `.fa.fai` index)
3. output_dir (can be the same as step 2's output_dir)
4. background_fraction (fraction of consensus UMRs to base the background set on, e.g. 1.0 for the same count, 0.2 for 20% - must be > 0 and <= 1.0)
5. seed (integer random seed, for reproducible subsampling/shuffling)
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro (bedtools)
9. account_department

**22-UMR_featurecounts_sbatch.sh** (array job - run after step 2's job finishes):
1. sample_list.txt (same prefixes used in steps 1-2)
2. file_suffix (BAM suffix; matched as `<sample_prefix>*<file_suffix>`, tolerating extra text in between)
3. saf_file (step 2's `<out_prefix>.umr.merged.consensus.noALT.saf`)
4. input_dir (BAM directory)
5. output_dir
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro
9. account_department

**23-UMR_featurecounts_summary_sbatch.sh** (single job, not array - run after step 3's array job finishes for all samples):
1. sample_list.txt (same prefixes used in steps 1-3)
2. counts_dir (step 3's output_dir, containing `<sample_prefix>.featurecounts.counts.summary` files)
3. output_dir
4. out_prefix (used to name the summary table)
5. walltime (HH:MM:SS)
6. memory (GB)
7. conda_enviro
8. account_department

**24-UMR_combine_calls_sbatch.sh** (single job, not array - run after step 3's array job finishes for all samples):
1. sample_list.txt (same prefixes used in steps 1-3)
2. counts_dir (step 3's output_dir, containing `<sample_prefix>.featurecounts.counts` files)
3. output_dir
4. out_prefix (used to name the combined matrix/CPM tables)
5. batch_size (target UMRs per batch; number of batches is computed automatically)
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro (R with edgeR + tibble)
9. account_department

**25-UMR_calls_sbatch.sh** (array job, one task per batch - run after step 5's job finishes):
1. batch_list.txt (step 5's `<output_dir>/batches/batch_list.txt`)
2. output_dir
3. walltime (HH:MM:SS)
4. memory (GB)
5. conda_enviro (numpy, statsmodels, findpeaks)
6. account_department

**26-UMR_calls_table_sbatch.sh** (single job, not array - run after step 6's array job finishes for all batches):
1. batch_list.txt (same file used in step 6)
2. sample_list.txt (same prefixes used in steps 1-5; defines the output table's column order)
3. calls_dir (step 6's output_dir, containing `<batch_id>.calls` files)
4. output_dir
5. out_prefix (used to name the final call table)
6. walltime (HH:MM:SS)
7. memory (GB)
8. account_department

**27-UMR_calls_qc_plots_sbatch.sh** (single job, not array - optional, run any time after step 7):
1. calls_table (step 7's `<out_prefix>.UMR.calls.tsv`)
2. cpm_matrix (step 5's `<out_prefix>.umr_counts.cpm.tsv`)
3. output_dir
4. n_umrs (number of random called UMRs to plot)
5. walltime (HH:MM:SS)
6. memory (GB)
7. conda_enviro (numpy, statsmodels, findpeaks, matplotlib)
8. account_department

**33-UMR_coverage_sbatch.sh** (array job - run after step 2's job finishes; alternative to step 3, for the within-sample workflow):
1. sample_list.txt
2. file_suffix (BAM suffix; matched as `<sample_prefix>*<file_suffix>`, tolerating extra text in between)
3. consensus_bed (step 2's `<out_prefix>.umr.merged.consensus.noALT.bed`, or step 2b's `<consensus_bed_basename>.umr_plus_background.bed` if using background/noise regions)
4. input_dir (BAM directory)
5. output_dir
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro (mosdepth)
9. account_department

**34-UMR_within_sample_calls_sbatch.sh** (array job, one task per sample - run after step 9's job finishes):
1. sample_list.txt (same prefixes used in step 9)
2. coverage_dir (step 9's output_dir, containing `<sample_prefix>.regions.bed.gz` files)
3. output_dir
4. shift (fraction of the distance from the 2nd valley to the neighbouring peak to shift the cutoff towards, e.g. 0.2)
5. bw (KDE bandwidth selector, `sj` (Sheather-Jones plug-in via KDEpy - recommended) or `normal_reference` (statsmodels' rule-of-thumb default))
6. walltime (HH:MM:SS)
7. memory (GB)
8. conda_enviro (numpy, statsmodels, findpeaks, KDEpy, matplotlib)
9. account_department

**35-UMR_within_sample_calls_table_sbatch.sh** (single job, not array - run after step 10's array job finishes for all samples):
1. sample_list.txt (same prefixes used in steps 9-10; defines the output table's column order)
2. calls_dir (step 10's output_dir, containing `<sample_prefix>.coverage.calls.tsv` files)
3. output_dir
4. out_prefix (used to name the final call table)
5. walltime (HH:MM:SS)
6. memory (GB)
7. conda_enviro
8. account_department

## Python Script Arguments

**recombine_bigwig.py:**
```
python recombine_bigwig.py <input.bw> <conversion_table.csv> <output.bw> <sample_prefix> <output_dir>
```

**recombine_bed.py:**
```
python recombine_bed.py <input.bed> <conversion_table.csv> <output.bed> <sample_prefix> <output_dir> [--no-sort]
```

- `sample_prefix` - creates unique temp file names, avoiding clashes when multiple samples run in parallel
- `output_dir` - directory where intermediate files are written (keeps working directory clean)

**20-EPIC2_reformat.py:**
```
python 20-EPIC2_reformat.py <input.bed> <output.names.bed> <sample_prefix>
```

**21-UMR_consensus_merge.py:**
```
python 21-UMR_consensus_merge.py <all_umr.bed> <all_umr.merged.bed> [--length-multiplier 10] [--ratio-threshold 0.5]
```

**21-UMR_consensus_bin.py:**
```
python 21-UMR_consensus_bin.py <input.bed> <output.bed> <bin_size>
```
- Splits each interval in `input.bed` (chrom, start, end, id, ...) into consecutive `bin_size`bp bins, trimming leftover bp evenly from both ends first; bins are named `<id>.<n>` (1-based); intervals shorter than `bin_size` are retained untrimmed as a single `<id>.0` bin instead of being split (counted and reported, not an error). Output is BED4

**23-UMR_featurecounts_summary.py:**
```
python 23-UMR_featurecounts_summary.py <sample_list.txt> <counts_dir> <output_tsv>
```

**24-UMR_combine_calls_split.py:**
```
python 24-UMR_combine_calls_split.py <cpm.tsv> <output_dir> <batch_size>
```

**24-UMR_combine_calls_cpm.R:**
```
Rscript 24-UMR_combine_calls_cpm.R <input.tsv> <output_cpm.tsv> <output_cpm_flt.tsv>
```

**25-UMR_calls.py** (also reused directly by `27-UMR_calls_qc_plots.sh`):
```
python 25-UMR_calls.py <batch_tsv> <output_dir> [--plots PLOT_DIR]
```

**34-UMR_within_sample_calls.py:**
```
python 34-UMR_within_sample_calls.py <regions.bed.gz> <sample_prefix> <output_dir> [--shift 0.2] [--bw {sj,normal_reference}] [--plots PLOT_DIR]
```

**35-UMR_within_sample_calls_table.py:**
```
python 35-UMR_within_sample_calls_table.py <sample_list.txt> <calls_dir> <output_tsv>
```

## Dependencies

- **BigWig pipeline**: pandas, UCSC tools (bigWigToBedGraph, bedGraphToBigWig)
- **BED pipeline**: pandas
- **UMR Consensus pipeline**: bedtools, featureCounts/subread, R (edgeR, tibble), numpy, statsmodels, findpeaks, matplotlib (otherwise Python steps use only the standard library)
- **UMR Within-Sample Calling pipeline** (alternative to phases 5-7): mosdepth, numpy, statsmodels, findpeaks, KDEpy, matplotlib
- **Background regions** (optional add-on to phase 2): bedtools (same dependency as the main UMR Consensus pipeline)
- **Trimming**: trim_galore, fastqc, cutadapt (via conda)

## Conversion Table Format

CSV with columns: `seqname_part, seqname, start_convert_to_part, end`
Maps split chromosome names to full names with coordinate offsets.
