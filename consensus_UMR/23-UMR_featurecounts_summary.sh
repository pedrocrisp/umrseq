#!/bin/bash -l
#SBATCH --job-name 23-UMR_fc_summary
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - Step 4: read support summary table #################
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

########## Set up cohort #################

mkdir -p $OUTPUT_DIR

OUTPUT_TSV="${OUTPUT_DIR}/${OUT_PREFIX}.featurecounts_summary.tsv"

# Check that every sample's featureCounts summary file from step 3 is present
while IFS= read -r SAMPLE_PREFIX; do
    [ -z "$SAMPLE_PREFIX" ] && continue
    SUMMARY_FILE="${COUNTS_DIR}/${SAMPLE_PREFIX}.featurecounts.counts.summary"
    if [ ! -f "$SUMMARY_FILE" ]; then
        echo "ERROR: Summary file not found (did step 3 finish for this sample?): $SUMMARY_FILE"
        exit 1
    fi
done < "$LIST"

########## Run #################

echo "Building read support summary table at $(date)"

# Run the Python script from the git repository folder (note: this location is hard coded)
python ~/gitrepos/AI_code_dev_testing/23-UMR_featurecounts_summary.py \
    "$LIST" \
    "$COUNTS_DIR" \
    "$OUTPUT_TSV"

if [ -f "$OUTPUT_TSV" ]; then
    echo "SUCCESS: $OUTPUT_TSV ($(wc -l < "$OUTPUT_TSV") lines)"
else
    echo "ERROR: Output file was not created: $OUTPUT_TSV"
    exit 1
fi

echo "Completed read support summary at $(date)"
