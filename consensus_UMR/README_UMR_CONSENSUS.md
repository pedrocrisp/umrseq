# UMR Consensus Pipeline

Builds a cohort consensus set of unmethylated regions (UMRs) from per-sample
UMR BED files (e.g. epic2 calls), in the two-tier SLURM array job pattern used
elsewhere in this repo.

Also calculates, per sample, how many read pairs support each consensus UMR
(read support / featureCounts step), summarises that into a per-sample read
support table, and finally calls each UMR present/absent per sample from the
across-sample distribution of its read support (steps 1-8 below).

For experiments with only a handful of samples - too few to model a
per-locus distribution across samples - there's an alternative calling
workflow (steps 9-11, "within-sample calling") that models each *sample's*
distribution of coverage across all UMRs instead. It reuses the same
cohort consensus from step 2.

There's also an optional add-on to step 2 (step 2b, "background regions")
that samples random non-UMR regions from the genome to give the
within-sample workflow a genuine low-coverage "noise" population to call
against - see "Background regions (step 2b)" below.

Step 2 also splits every consensus UMR into fixed-size consecutive sub-bins
(e.g. 50bp), for analyses that need finer-grained intervals than whole UMRs -
see "Binning (step 2)" below.

This replaces the ad-hoc scripts in `2.consensus.pe/` (`1.make_consensus.slm`),
`3.calculate_support.pe.fc/` (`1.format_bed.sh`, `2.featurecounts.slm`),
`5.across_samples.pe.v2/` (`1.combine.fc.slm`, `2.split.sh`, `3.make_calls.slm`,
`4.make_sample_plots.slm`, `5.make_call_table.sh`), `3.calculate_support.pe.md/`
(`1.mosdepth.slm`), and `4.within_samples.pe/` (`1.make_calls.slm`,
`2.combine_calls.sh`), which hardcoded a working directory and manually
maintained sample-to-ID / sample-to-BAM mapping files (`list1.txt`,
`list.f.txt`, `list.n.txt`, `list.txt`, `list2.txt`). This module instead
takes a plain sample list (one prefix per line, like the other pipelines in
this repo) and derives IDs and file paths automatically, so it can run on
any dataset.

## Why so many trios

The pipeline has phases that don't fit into a single two-tier job - some need
every sample's (or every UMR's) output at once, so they're a single job
rather than an array job:

1. **Per-sample ID assignment** - array job, one task per sample. Each task
   reads a sample's UMR BED file and appends a unique ID to every interval
   (`<sample>_UMR_<9-digit counter>`), so IDs are guaranteed unique once
   every sample's output is combined.
2. **Cohort merge** - single job. Needs *every* sample's output at once
   (concatenate, sort, `bedtools merge`, then collapse overlapping UMRs from
   different samples into a consensus interval, then convert to SAF for
   featureCounts). Also splits each consensus UMR into fixed-size sub-bins
   (see "Binning" below) and writes binned BED/SAF equivalents.
3. **Per-sample read support** - array job, one task per sample. Each task
   runs `featureCounts` for one sample's BAM file against the cohort
   consensus SAF annotation from phase 2.
4. **Read support summary** - single job. Needs every sample's featureCounts
   output at once to build one table.
5. **Combine counts, CPM-normalise, batch** - single job. Needs every
   sample's counts at once to build a UMR x sample matrix, then splits the
   *UMRs* (not samples) into batches for phase 6.
6. **Per-batch UMR calling** - array job, one task per *batch of UMRs* (not
   per sample - the model needs every sample's value for a UMR at once, so
   batching by UMR is what makes this parallelisable).
7. **Call table aggregation** - single job. Needs every batch's calls at once
   to build one table.
8. *(Optional)* **QC plots** - single job, run any time after phase 7.
   Re-runs phase 6's calling logic with plotting turned on, for a random
   subset of called UMRs only (too slow to plot every UMR in a full run).

There's also an optional add-on to phase 2 (step 2b, not numbered into the
sequence below since it's neither required nor sequential - see "Background
regions" below): randomly samples non-UMR regions from the genome, matching
the consensus UMR length distribution, to give the within-sample workflow
(phases 9-11) a genuine low-coverage population to call against.

There's also an alternative to phases 5-7, for cohorts too small to model a
per-locus distribution across samples (see "Within-sample calling workflow"
below):

9. **Per-sample UMR coverage** - array job, one task per sample. Runs
   `mosdepth` to get each sample's mean read depth over every consensus UMR.
10. **Per-sample presence/absence calling** - array job, one task per
    sample (not per locus - the model needs every UMR's value for one sample
    at once, so batching by sample is what makes this parallelisable).
11. **Call table aggregation** - single job. Needs every sample's calls at
    once to build one table.

So there are six script trios plus one optional trio for the main
(across-sample) workflow, one more optional trio that adds background
regions to the consensus (step 2b), and three more trios for the alternative
(within-sample) workflow (some have no `.py`/`.R` to call directly, or no
per-sample job logic beyond reading files), run one after the other:

- `20-EPIC2_reformat_sbatch.sh` -> `20-EPIC2_reformat.sh` -> `20-EPIC2_reformat.py`
  (array job, phase 1)
- `21-UMR_consensus_merge_sbatch.sh` -> `21-UMR_consensus_merge.sh` -> `21-UMR_consensus_merge.py` + `21-UMR_consensus_bin.py`
  (single job, phase 2)
- `22-UMR_featurecounts_sbatch.sh` -> `22-UMR_featurecounts.sh`
  (array job, phase 3 - calls `featureCounts` directly, no Python needed)
- `23-UMR_featurecounts_summary_sbatch.sh` -> `23-UMR_featurecounts_summary.sh` -> `23-UMR_featurecounts_summary.py`
  (single job, phase 4)
- `24-UMR_combine_calls_sbatch.sh` -> `24-UMR_combine_calls.sh` -> `24-UMR_combine_calls_cpm.R` + `24-UMR_combine_calls_split.py`
  (single job, phase 5)
- `25-UMR_calls_sbatch.sh` -> `25-UMR_calls.sh` -> `25-UMR_calls.py`
  (array job, phase 6)
- `26-UMR_calls_table_sbatch.sh` -> `26-UMR_calls_table.sh`
  (single job, phase 7 - pure bash, no Python needed)
- `27-UMR_calls_qc_plots_sbatch.sh` -> `27-UMR_calls_qc_plots.sh` -> (reuses `25-UMR_calls.py --plots`)
  (single job, optional phase 8)
- `21b-UMR_consensus_merge_background_sbatch.sh` -> `21b-UMR_consensus_merge_background.sh`
  (single job, optional step 2b - calls `bedtools shuffle` directly, no Python needed)

Within-sample calling workflow (alternative to phases 5-7):

- `33-UMR_coverage_sbatch.sh` -> `33-UMR_coverage.sh`
  (array job, phase 9 - calls `mosdepth` directly, no Python needed)
- `34-UMR_within_sample_calls_sbatch.sh` -> `34-UMR_within_sample_calls.sh` -> `34-UMR_within_sample_calls.py`
  (array job, phase 10)
- `35-UMR_within_sample_calls_table_sbatch.sh` -> `35-UMR_within_sample_calls_table.sh` -> `35-UMR_within_sample_calls_table.py`
  (single job, phase 11)

## Usage

### Step 1: assign per-sample UMR IDs (array job)

```bash
bash 20-EPIC2_reformat_sbatch.sh \
    samples.txt \
    .UMR.epic2.bed \
    ./umr_calls \
    ./umr_names \
    1:00:00 \
    2 \
    myenv \
    my_department
```

Wait for every array task to finish successfully (`squeue -u $USER`), then:

### Step 2: build cohort consensus (single job)

```bash
bash 21-UMR_consensus_merge_sbatch.sh \
    samples.txt \
    .UMR.epic2.bed \
    ./umr_names \
    ./umr_consensus \
    all_samples \
    50 \
    4:00:00 \
    8 \
    myenv \
    my_department
```

`samples.txt` and the file suffix must match what was used in step 1 - step 2
uses them to find each sample's `<sample><suffix>.names` file in `umr_names`.
`bin_size` (`50` here) controls the size of the sub-bins each consensus UMR
is split into for the binned outputs - see "Binning (step 2)" below; pick
whatever bin size your downstream analysis needs (e.g. `100`).

### Step 3: count per-sample read support (array job)

```bash
bash 22-UMR_featurecounts_sbatch.sh \
    samples.txt \
    .pe.rd.bam \
    ./umr_consensus/all_samples.umr.merged.consensus.noALT.saf \
    ./bams \
    ./umr_counts \
    4:00:00 \
    8 \
    myenv \
    my_department
```

`samples.txt` should use the same sample prefixes as steps 1-2. BAM files are
matched as `<input_dir>/<sample_prefix>*<file_suffix>`, so any extra text
between the prefix and suffix (e.g. a cultivar name) doesn't need to be
listed anywhere - the job fails loudly if zero or more than one BAM matches a
sample.

### Step 4: build the read support summary table (single job)

```bash
bash 23-UMR_featurecounts_summary_sbatch.sh \
    samples.txt \
    ./umr_counts \
    ./umr_counts \
    all_samples \
    0:30:00 \
    2 \
    myenv \
    my_department
```

This parses each sample's `<sample_prefix>.featurecounts.counts.summary`
file (written by `featureCounts` alongside its counts table in step 3) - not
the verbose stdout log - since the summary file is a clean TSV and its row
totals already match what the log reports (e.g. summing every row reproduces
the log's "Total alignments" exactly). Output: one row per sample with total
reads, assigned reads, and percent assigned.

### Step 5: combine counts, CPM-normalise, and batch (single job)

```bash
bash 24-UMR_combine_calls_sbatch.sh \
    samples.txt \
    ./umr_counts \
    ./umr_calling \
    all_samples \
    1000 \
    3:00:00 \
    20 \
    myenv \
    my_department
```

Builds a UMR x sample counts matrix from step 3's featureCounts output (same
sample order as `samples.txt`), CPM-normalises it (edgeR), and splits the CPM
matrix into batches of UMRs - targeting `1000` UMRs per batch here - for
parallel calling in step 6. `conda_enviro` needs R with the `edgeR` and
`tibble` packages.

### Step 6: call each UMR present/absent per sample (array job)

```bash
bash 25-UMR_calls_sbatch.sh \
    ./umr_calling/batches/batch_list.txt \
    ./umr_calling/calls \
    2:00:00 \
    30 \
    myenv \
    my_department
```

One array task per batch (not per sample). Each task fits a KDE to every
UMR's per-sample CPM values, looks for a bimodal split, and calls samples
present/absent against the valley between the two modes - see "Calling
algorithm" below. `conda_enviro` needs `numpy`, `statsmodels`, and
`findpeaks`.

Wait for every array task to finish, then:

### Step 7: aggregate batches into the final call table (single job)

```bash
bash 26-UMR_calls_table_sbatch.sh \
    ./umr_calling/batches/batch_list.txt \
    samples.txt \
    ./umr_calling/calls \
    ./umr_calling \
    all_samples \
    0:30:00 \
    4 \
    my_department
```

Concatenates every batch's `.calls` file, recodes `YES`/`NO` as `1`/`0`, and
writes one table. The column order is rebuilt from `samples.txt` directly
(not read back from an arbitrary batch file), so it's always correct as long
as the same `samples.txt` is used in steps 5-7.

### Step 8 (optional): QC plots for a random subset of calls (single job)

```bash
bash 27-UMR_calls_qc_plots_sbatch.sh \
    ./umr_calling/all_samples.UMR.calls.tsv \
    ./umr_calling/all_samples.umr_counts.cpm.tsv \
    ./umr_calling/qc_plots \
    1000 \
    2:00:00 \
    8 \
    myenv \
    my_department
```

Samples `1000` random UMRs that were called in step 7, and re-runs
`25-UMR_calls.py` on just those (with `--plots` turned on) to save a KDE plot
and a peak/valley plot per UMR - a quick visual sanity check on the calling
cutoffs without plotting every UMR in the full run. Can be run any time after
step 7; not part of the core pipeline output.

## Within-sample calling workflow (alternative to steps 5-7)

Steps 5-7 model each *UMR's* distribution of values across all samples,
which needs a large, diverse cohort (e.g. >100 samples) to get a usable
distribution per locus. For experiments with only a handful of samples,
steps 9-11 instead model each *sample's* distribution of coverage across all
UMRs - so they need many UMRs but work fine with few samples. They reuse the
same cohort consensus from step 2, so run steps 1-2 first.

### Step 2b (optional): add background/noise regions

```bash
bash 21b-UMR_consensus_merge_background_sbatch.sh \
    ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed \
    genome.fa.fai \
    ./umr_consensus \
    1.0 \
    42 \
    1:00:00 \
    4 \
    myenv \
    my_department
```

A small cohort's UMR coverage values can end up all looking "present" (no
clear low-coverage population to call "absent" against), so step 10's KDE
has nothing to split into two modes. This step manufactures that low
population: it randomly subsamples `1.0` (i.e. 100%) of the consensus UMRs
in `consensus_bed` (here step 2's plain `noALT.bed`; pass step 2's binned
`noALT.<bin_size>.bed` instead if you want background regions matching the
bin length rather than whole-UMR length), then `bedtools shuffle`s them to
new genomic locations that don't overlap any consensus UMR (`-excl`) or
each other (`-noOverlapping`) - since `bedtools shuffle` preserves each
input interval's length, the background set has the same length
distribution as (a random subsample of) the input set. `genome_file` is a
tab-delimited chromosome sizes file (a samtools `.fa.fai` index works
directly, since its first two columns are `chrom` and `size`).
`background_fraction` controls how many background
regions are generated relative to the UMR count - `1.0` (the same count)
gives the most robust low-coverage KDE peak in step 10 at the cost of
doubling the loci mosdepth has to measure in step 9; lower it (e.g. `0.2`)
if that cost matters more than peak robustness for your cohort. `seed`
makes the subsampling/shuffling reproducible.

Produces a standalone background BED/SAF (region IDs prefixed `BG_`, see
"Outputs" below) and a combined `<consensus_bed_basename>.umr_plus_background.bed`/`.saf`
(e.g. `all_samples.umr.merged.consensus.noALT.umr_plus_background.bed` for
the example above) - output filenames are derived from `consensus_bed`'s own
name, not a separate prefix, so background runs against different
`consensus_bed` inputs (e.g. whole-UMR vs binned) never clash in the same
`output_dir`. Use the combined BED as step 9's `consensus_bed` argument (in
place of step 2's plain consensus BED) to carry the background regions
through coverage measurement and within-sample calling. The combined table that step 11
produces will then include `BG_*` rows alongside `CON_UMR_*` rows - filter
on the `UMR_ID` column's prefix if you want to drop or separately inspect
the background calls (e.g. the fraction of background regions called `YES`
is a rough false-positive-rate estimate for that sample's cutoff).

### Step 9: per-sample UMR coverage (array job)

```bash
bash 33-UMR_coverage_sbatch.sh \
    samples.txt \
    .pe.rd.bam \
    ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed \
    ./bams \
    ./umr_coverage \
    4:00:00 \
    8 \
    myenv \
    my_department
```

Runs `mosdepth` per sample to get the mean read depth over every consensus
UMR interval (the same consensus BED step 2 produced for the across-sample
workflow's SAF file - this workflow uses the plain BED directly). If you ran
step 2b, pass its `<consensus_bed_basename>.umr_plus_background.bed` instead,
to also measure coverage over the background/noise regions. BAM matching and
validation work the same way as step 3 (glob match, fail loudly on
zero/multiple matches); a BAM index (`.bai`/`.csi`) is also required.

### Step 10: per-sample presence/absence calling (array job)

```bash
bash 34-UMR_within_sample_calls_sbatch.sh \
    samples.txt \
    ./umr_coverage \
    ./umr_within_sample_calls \
    0.2 \
    sj \
    1:00:00 \
    4 \
    myenv \
    my_department
```

One array task per sample (not per UMR). Each task fits a KDE to that
sample's UMR coverage values, looks for a bimodal split, and - if found -
calls every UMR present/absent for that sample against a cutoff shifted from
the valley towards a peak by the `0.2` shift fraction here - see "Calling
algorithm" below. KDE bandwidth is chosen with the `bw` argument here (`sj`
or `normal_reference`, see "Calling algorithm" below for the tradeoff).
Samples whose coverage distribution isn't bimodal are skipped (logged as a
warning, not a job failure) since that's an expected outcome for some
samples, not an error. `conda_enviro` needs `numpy`, `statsmodels`,
`findpeaks`, `KDEpy`, and `matplotlib` (a KDE plot and a peak/valley plot are
saved for every sample, including skipped ones, so a non-bimodal sample's
distribution can still be inspected - there are few samples, so plotting all
of them is cheap).

Wait for every array task to finish, then:

### Step 11: aggregate per-sample calls into the final table (single job)

```bash
bash 35-UMR_within_sample_calls_table_sbatch.sh \
    samples.txt \
    ./umr_within_sample_calls \
    ./umr_within_sample_calls \
    all_samples \
    0:30:00 \
    2 \
    myenv \
    my_department
```

Joins every sample's calls into one `UMR_ID x sample` table, recoding
`YES`/`NO` as `1`/`0`. Samples with no calls file from step 10 (a non-bimodal
coverage distribution) are filled with `NA` for every UMR rather than
treated as an error. The column order is taken directly from `samples.txt`.

## Outputs

**Step 2** (in step 2's output_dir, named `<out_prefix>...`):

- `<out_prefix>.umr.bed` - every sample's UMRs, concatenated and sorted, with unique IDs
- `<out_prefix>.umr.merged.bed` - `bedtools merge` output, overlapping UMRs collapsed with `|`-delimited IDs
- `<out_prefix>.umr.merged.consensus.bed` - consensus UMRs (`CON_UMR_*`, plus `ALT_CON_UMR_*` where the median and full-span intervals disagree by more than the ratio threshold) with member/dropped IDs in columns 5-6
- `<out_prefix>.umr.merged.consensus.fmt.bed` - consensus intervals only (BED4, name column set to `<out_prefix>.consensus`)
- `<out_prefix>.umr.merged.consensus.noALT.bed` - consensus intervals excluding `ALT_CON_UMR_*` rows
- `<out_prefix>.umr.merged.consensus.noALT.saf` - the same intervals in SAF format (`GeneID, Chr, Start (1-based), End, Strand`), ready for `featureCounts` - this is the file step 3 needs
- `<out_prefix>.umr.merged.consensus.<bin_size>.bed` - `<out_prefix>.umr.merged.consensus.bed`'s intervals (including `ALT_CON_UMR_*`) split into `<bin_size>`bp sub-bins, BED4, named `<parent_id>.<n>`
- `<out_prefix>.umr.merged.consensus.noALT.<bin_size>.bed` - same, but from `noALT.bed` (excludes `ALT_CON_UMR_*`)
- `<out_prefix>.umr.merged.consensus.noALT.<bin_size>.saf` - the binned `noALT` intervals in SAF format

**Step 2b** (optional, in step 2b's output_dir, named after `consensus_bed`'s own basename - i.e. `<consensus_bed_basename>...`, where `consensus_bed_basename` is `consensus_bed` with its `.bed` extension stripped, e.g. `all_samples.umr.merged.consensus.noALT`):

- `<consensus_bed_basename>.subsample_for_background.bed` - the random subsample of `consensus_bed`'s intervals used as the background length template (intermediate file, kept for inspection)
- `<consensus_bed_basename>.background.shuffled.bed` - the subsample after `bedtools shuffle` but before ID assignment (intermediate file)
- `<consensus_bed_basename>.background.bed` - the final background regions (`BG_*` IDs), BED4
- `<consensus_bed_basename>.background.saf` - the same regions in SAF format
- `<consensus_bed_basename>.umr_plus_background.bed` - `consensus_bed` and `<consensus_bed_basename>.background.bed` combined and sorted - this is the file to pass as step 9's `consensus_bed` if you want background regions included
- `<consensus_bed_basename>.umr_plus_background.saf` - the same combined regions in SAF format

**Step 3** (in step 3's output_dir): `<sample_prefix>.featurecounts.counts` (plus the `.summary` file `featureCounts` writes alongside it) for every sample.

**Step 4** (in step 4's output_dir): `<out_prefix>.featurecounts_summary.tsv`, columns `sample`, `total_reads`, `assigned_reads`, `percent_assigned`.

**Step 5** (in step 5's output_dir, named `<out_prefix>...`):

- `<out_prefix>.umr_counts.tsv` - UMR x sample raw read count matrix
- `<out_prefix>.umr_counts.cpm.tsv` - the same matrix, CPM-normalised
- `<out_prefix>.umr_counts.cpm.flt.tsv` - CPM matrix filtered to UMRs with CPM >= 0.1 in at least 2 samples (not used downstream by default, kept for inspection - same as the original pipeline's `.cpm.flt` file)
- `batches/batch0.tsv`, `batches/batch1.tsv`, ... - the CPM matrix split into UMR batches
- `batches/batch_list.txt` - list of batch file paths, one per line - this is what drives step 6's array job

**Step 6** (in step 6's output_dir): per batch, `<batch_id>.calls` (UMR_ID + YES/NO per sample, for UMRs with a confident bimodal split) and `<batch_id>.UMR.stats.txt` (UMR_ID, valley count, peak count - diagnostic).

**Step 7** (in step 7's output_dir): `<out_prefix>.UMR.calls.tsv` - every called UMR, one row each, with `1`/`0` per sample.

**Step 8** (in step 8's output_dir): `qc_sample.umr_ids.txt` (the sampled UMR IDs), `qc_sample.cpm.tsv` (their CPM rows), and `plots/<umr_id>.plot1.bi.png` / `plots/<umr_id>.plot2.bi.png` (KDE and peak/valley plots with the cutoff marked) for each.

**Step 9** (in step 9's output_dir): `<sample_prefix>.regions.bed.gz` (mosdepth output - consensus BED columns plus mean depth) and the other `mosdepth` summary files it writes alongside, for every sample.

**Step 10** (in step 10's output_dir): per sample, `<sample_prefix>.coverage.calls.tsv` (chrom, start, end, UMR_ID, depth, YES/NO - only written if a bimodal split was found), `<sample_prefix>.coverage.stats.txt` (sample, bw method, bw value, valley count, peak count, bimodal Y/N, cutoff - always written, diagnostic), and `plots/<sample_prefix>.plot1.bi.pdf` / `plots/<sample_prefix>.plot2.bi.pdf` (KDE and peak/valley plots, written for every sample including skipped ones, so a non-bimodal sample's distribution can still be inspected - the cutoff line is omitted when no cutoff was found).

**Step 11** (in step 11's output_dir): `<out_prefix>.UMR.within_sample.calls.tsv` - every UMR, one row each, with `1`/`0`/`NA` per sample (`NA` for samples step 10 couldn't call).

## Consensus algorithm

For each set of UMRs that `bedtools merge` collapsed together:

1. Compute the median UMR length among the group.
2. Drop any UMR longer than `--length-multiplier` (default 10x) the median - removes outliers that would otherwise distort the consensus.
3. Take the median start and median end of the remaining UMRs as the consensus interval, and the min-start/max-end as the full-span interval.
4. If the median interval spans less than `--ratio-threshold` (default 0.5) of the full-span interval, report both the full-span interval (`CON_UMR_*`) and the tighter median interval (`ALT_CON_UMR_*`); otherwise report only the median interval as `CON_UMR_*`.

Both thresholds are exposed as optional flags on `21-UMR_consensus_merge.py`
if you want to tune them - edit the `python ... 21-UMR_consensus_merge.py`
call in `21-UMR_consensus_merge.sh` to pass `--length-multiplier` /
`--ratio-threshold`.

## Binning (step 2)

`21-UMR_consensus_bin.py` splits each consensus UMR into consecutive,
non-overlapping `bin_size`bp bins:

1. If a UMR's length isn't an exact multiple of `bin_size`, the leftover bp
   are trimmed evenly from both ends first (the shorter side gets any odd
   extra bp), so every bin comes out exactly `bin_size` long.
2. The trimmed interval is then cut into consecutive `bin_size`bp bins.
3. Each bin is named `<parent_id>.<n>` (1-based), e.g. `CON_UMR_000000001.1`,
   `CON_UMR_000000001.2`, ...
4. UMRs shorter than `bin_size` aren't split - instead the whole (untrimmed)
   UMR is kept as a single bin named `<parent_id>.0`. These are counted and
   reported on stderr, not treated as an error.

It's run twice in step 2 - once on `umr.merged.consensus.bed` and once on
`umr.merged.consensus.noALT.bed` - producing the matching `.<bin_size>.bed`
files (plus a SAF conversion of the `noALT` version), so downstream tools
that want per-UMR resolution finer than a whole UMR (e.g. binned coverage or
methylation profiles) can use these instead of the whole-UMR consensus.
`bin_size` is a plain argument to `21-UMR_consensus_merge_sbatch.sh` - to get
multiple bin sizes (e.g. `50` and `100`), just re-run step 2 with a different
`bin_size`: the binned filenames already encode the size, so they won't
clash, and the un-binned consensus files are identical between runs (safe to
overwrite).

## Background regions (step 2b)

`21b-UMR_consensus_merge_background.sh` builds the background/noise set in
four steps:

1. Randomly subsample `background_fraction` of the consensus UMRs (seeded,
   without replacement) - this is just to pick which UMR *lengths* to reuse,
   not which genomic positions.
2. `bedtools shuffle` those subsampled intervals to new genomic positions,
   excluding any overlap with a consensus UMR (`-excl`) or with each other
   (`-noOverlapping`); since `shuffle` only moves intervals, not resizes
   them, each background region's length exactly matches the UMR it was
   subsampled from - so the background set's length distribution matches
   (a random sample of) the UMR set's, by construction, regardless of
   `background_fraction`.
3. Sort and assign each background region a unique `BG_<9-digit counter>`
   ID (parallel to step 2's `CON_UMR_<9-digit counter>`).
4. Convert to SAF, and concatenate+sort with step 2's consensus BED/SAF to
   produce the combined `umr_plus_background` files.

`background_fraction` trades off two things: a larger fraction (up to `1.0`)
gives more background data points, which makes the low-coverage population
step 10's KDE has to detect smoother and more robust to detect as a distinct
peak; a smaller fraction (e.g. `0.2`) means fewer extra loci for step 9's
`mosdepth` to measure, at the cost of a noisier, less reliable background
peak estimate. `1.0` is the safer default if you're not sure - the
background regions don't pollute the real UMR calls (they're easily filtered
out of step 11's table by their `BG_` ID prefix), so there's little downside
to generating more of them beyond the extra mosdepth compute.

## featureCounts flags (step 3)

`22-UMR_featurecounts.sh` runs `featureCounts -F SAF -p -C -B -P -d 50 -D 1000 -Q 10`:
paired-end, only count read pairs with both reads mapped, drop chimeric
fragments, enforce a 50-1000bp fragment length, and require MAPQ >= 10.
These are fixed in the script (edit directly if your library prep needs
different thresholds), matching the original `2.featurecounts.slm`.

## Calling algorithm (steps 6 and 8)

For each UMR, using its CPM value in every sample:

1. Trim the top 2% (outliers), then fit a kernel density estimate (KDE) over the remaining values.
2. Find peaks and valleys in the density curve (`findpeaks`, peakdetect method).
3. Only call the UMR if the shape looks bimodal: exactly 3 valleys with 1-2 peaks, or more than 3 valleys where the peaks past the 3rd valley are all smaller than the peaks before it. Otherwise skip the UMR (no call) - the distribution doesn't have a clear two-population split to threshold on.
4. Use the 2nd valley as the present/absent cutoff: samples with CPM above it are called `YES`, at or below are `NO`.
5. Only keep the call if both groups have at least 5% of samples - drops UMRs where the "split" is really just a handful of outliers.

This is unchanged from the original `epitype.v2.py` - same trim fraction,
peak-detection method, and thresholds. `25-UMR_calls.py` is shared by both
the core calling step (6) and the QC plotting step (8); pass `--plots <dir>`
to additionally save the two diagnostic PNGs per called UMR (this is the
only behavioural difference from the original `epitype.v2.p.py`, beyond one
bug fix: the marked cutoff line on the peak/valley plot now uses the actual
CPM cutoff value, not the KDE sample index).

## Calling algorithm (step 10)

For each sample, using its mosdepth mean depth value at every UMR:

1. Trim the top 5% (outliers), then fit a KDE over the remaining values, with bandwidth chosen by `--bw` (default/recommended `sj`):
   - `sj` - Sheather-Jones plug-in bandwidth, computed via `KDEpy`'s ISJ implementation (statsmodels has no built-in SJ selector) and passed into statsmodels as a fixed numeric bandwidth. SJ adapts to the data's actual shape rather than assuming a unimodal Gaussian reference, so in principle it's less likely than a rule-of-thumb selector to oversmooth two real coverage populations into one. In practice, with this step's strict "exactly 3 valleys" bimodal test, SJ's narrower, more data-adaptive bandwidth can also pick up small spurious sub-peaks within a tight low- or high-coverage population (especially when the two populations have very different spreads) and cause a genuinely bimodal sample to fail the bimodal check - if a sample you expect to be bimodal is being skipped, check its `--plots` output and try `--bw normal_reference` for comparison.
   - `normal_reference` - statsmodels' default rule-of-thumb (Scott-like constant x `min(std, IQR/1.349)` x `n^-1/5`); tends to oversmooth multimodal data in general, but that extra smoothing can also suppress the kind of spurious sub-peaks `sj` is prone to above.
2. Find peaks and valleys in the density curve (`findpeaks`, peakdetect method, `lookahead=100`).
3. Only call the sample if the shape looks bimodal: exactly 3 valleys with 1-2 peaks. Otherwise skip the sample entirely (no calls written) - its UMR coverage doesn't have a clear two-population split to threshold on.
4. Use the 2nd valley, shifted towards the neighbouring peak by `--shift` (default `0.2`, i.e. 20% of the way from the valley to the peak), as the present/absent cutoff: UMRs with depth above it are called `YES`, at or below are `NO`.

The bandwidth actually used by statsmodels (a single float, even for `sj`) is recorded per sample in `<sample_prefix>.coverage.stats.txt` for diagnostics.

This is the same model as steps 6/8 (KDE + peakdetect), but fit across UMRs
within one sample rather than across samples for one UMR, and there's no
minimum-group-size filter (step 6's 5%-per-group check) - every UMR in a
successfully-called sample gets a call.

This is unchanged from the original `infer_absent.py` - same trim fraction,
lookahead, and shift logic. `34-UMR_within_sample_calls.py` fixes two bugs
present in the original:

- **Crash on non-bimodal samples**: the original always tried to plot using
  a cutoff variable that was only ever set inside the bimodal branch, so any
  sample that didn't produce exactly 3 valleys/1-2 peaks crashed with a
  `NameError` instead of being skipped. The new script checks for a bimodal
  split first and skips cleanly (with a logged reason) if there isn't one -
  it still saves the KDE and peak/valley plots for the skipped sample (just
  without a cutoff line), so the failed distribution can be inspected.
- **Destructive in-place decompression**: the original `gunzip`-ed each
  sample's `.regions.bed.gz` before calling `infer_absent.py`, deleting the
  only compressed copy of step 9's output. The new script reads the `.gz`
  directly (Python's `gzip` module) and never modifies step 9's output.

The original `combine_calls.py`'s sample-name parsing also had a bug
(`"TG001.regions.bed.calls".split(".")[0:2]` produced the column name
`"TG001.regions"`, not `"TG001"`); `35-UMR_within_sample_calls_table.py`
fixes this by taking sample names from `samples.txt` directly rather than
parsing them out of filenames.

## Requirements

- `bedtools` (must be available in `conda_enviro`, or load it via `module
  load` in `21-UMR_consensus_merge.sh` - also needed in
  `21b-UMR_consensus_merge_background.sh` if generating background regions)
- `featureCounts` / `subread` (must be available in `conda_enviro`, or load
  it via `module load` in `22-UMR_featurecounts.sh`)
- R with `edgeR` and `tibble` (must be available in `conda_enviro`, or load
  it via `module load` in `24-UMR_combine_calls.sh`)
- `numpy`, `statsmodels`, `findpeaks`, and (for step 8) `matplotlib` (must be
  available in `conda_enviro` for steps 6 and 8)
- `mosdepth` (must be available in `conda_enviro`, or load it via `module
  load` in `33-UMR_coverage.sh`) - only needed for the within-sample workflow
- `numpy`, `statsmodels`, `findpeaks`, and `matplotlib` (must be available in
  `conda_enviro` for step 10) - only needed for the within-sample workflow
- Otherwise, Python 3 standard library only (no pandas required)
