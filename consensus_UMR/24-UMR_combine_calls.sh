#!/bin/bash -l
#SBATCH --job-name 24-UMR_combine_calls
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Calling - Step 1: combine counts, CPM-normalise, batch #################
set -xeuo pipefail

echo ------------------------------------------------------
echo SBATCH: working directory is $SLURM_SUBMIT_DIR
echo SBATCH: job identifier is $SLURM_JOBID
echo ------------------------------------------------------

echo working dir is $PWD

#cd into work dir
echo changing to SLURM_SUBMIT_DIR
cd "$SLURM_SUBMIT_DIR"
echo working dir is now $PWD

########## Modules #################

module load miniconda3/23.9.0-0
source $EBROOTMINICONDA3/etc/profile.d/conda.sh
conda activate $conda_enviro

# R (with the edgeR and tidyverse packages) must be available in $conda_enviro
# above, or via a module load below - adjust for your cluster, e.g.:
# module load r/4.2.1-foss-2021a
module load r/4.4.2-gfbf-2024a

########## Set up cohort #################

mkdir -p $OUTPUT_DIR
BATCH_DIR="${OUTPUT_DIR}/batches"
mkdir -p "$BATCH_DIR"

RAW_MATRIX="${OUTPUT_DIR}/${OUT_PREFIX}.umr_counts.tsv"
CPM_MATRIX="${OUTPUT_DIR}/${OUT_PREFIX}.umr_counts.cpm.tsv"
CPM_FLT_MATRIX="${OUTPUT_DIR}/${OUT_PREFIX}.umr_counts.cpm.flt.tsv"

# Check that every sample's featureCounts counts file from step 3 is present
COUNTS_FILES=()
while IFS= read -r SAMPLE_PREFIX; do
    [ -z "$SAMPLE_PREFIX" ] && continue
    COUNTS_FILE="${COUNTS_DIR}/${SAMPLE_PREFIX}.featurecounts.counts"
    if [ ! -f "$COUNTS_FILE" ]; then
        echo "ERROR: Counts file not found (did step 3 finish for this sample?): $COUNTS_FILE"
        exit 1
    fi
    COUNTS_FILES+=("$COUNTS_FILE")
done < "$LIST"

echo "Found ${#COUNTS_FILES[@]} per-sample featureCounts files"

########## Run #################

echo "Building UMR x sample counts matrix at $(date)"

# UMR_ID column: featureCounts' Geneid column (1), sorted, from the first sample
{ echo "UMR_ID"; grep -v "^#" "${COUNTS_FILES[0]}" | grep -v "^Geneid" | LC_COLLATE=C sort -k1,1 | cut -f1; } > "${OUTPUT_DIR}/.col1.txt"

# Per-sample count column: featureCounts' count column (7), sorted to match
COV_FILES=()
while IFS= read -r SAMPLE_PREFIX; do
    [ -z "$SAMPLE_PREFIX" ] && continue
    COUNTS_FILE="${COUNTS_DIR}/${SAMPLE_PREFIX}.featurecounts.counts"
    COV_FILE="${OUTPUT_DIR}/.${SAMPLE_PREFIX}.cov.txt"
    { echo "$SAMPLE_PREFIX"; grep -v "^#" "$COUNTS_FILE" | grep -v "^Geneid" | LC_COLLATE=C sort -k1,1 | cut -f7; } > "$COV_FILE"
    COV_FILES+=("$COV_FILE")
done < "$LIST"

paste "${OUTPUT_DIR}/.col1.txt" "${COV_FILES[@]}" > "$RAW_MATRIX"
rm -f "${OUTPUT_DIR}/.col1.txt" "${COV_FILES[@]}"

echo "CPM-normalising counts matrix at $(date)"
Rscript ~/gitrepos/AI_code_dev_testing/24-UMR_combine_calls_cpm.R \
    "$RAW_MATRIX" \
    "$CPM_MATRIX" \
    "$CPM_FLT_MATRIX"

echo "Splitting CPM matrix into batches (target ${BATCH_SIZE} UMRs/batch) at $(date)"
python ~/gitrepos/AI_code_dev_testing/24-UMR_combine_calls_split.py \
    "$CPM_MATRIX" \
    "$BATCH_DIR" \
    "$BATCH_SIZE"

########## Check outputs #################

for f in "$RAW_MATRIX" "$CPM_MATRIX" "$CPM_FLT_MATRIX" "${BATCH_DIR}/batch_list.txt"; do
    if [ -f "$f" ]; then
        echo "SUCCESS: $f ($(wc -l < "$f") lines)"
    else
        echo "ERROR: Output file was not created: $f"
        exit 1
    fi
done

echo "Completed combine/CPM/split at $(date)"
