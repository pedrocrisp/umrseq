#!/bin/bash -l
#SBATCH --job-name 35-UMR_within_sample_calls_table
#SBATCH --requeue
#SBATCH --partition=general

########## Within-sample UMR Calling - Step 3: aggregate per-sample calls into final table #################
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

conda activate $conda_enviro

########## Set up cohort #################

mkdir -p $OUTPUT_DIR

CALLS_TABLE="${OUTPUT_DIR}/${OUT_PREFIX}.UMR.within_sample.calls.tsv"

########## Run #################

echo "Building within-sample UMR calls table at $(date)"

# Run the Python script from the git repository folder (note: this location is hard coded)
# Samples with no '<sample_prefix>.coverage.calls.tsv' (non-bimodal coverage
# distribution in step 2) are filled with NA rather than treated as an error
python ~/gitrepos/AI_code_dev_testing/35-UMR_within_sample_calls_table.py \
    "$SAMPLE_LIST" \
    "$CALLS_DIR" \
    "$CALLS_TABLE"

########## Check outputs #################

if [ -f "$CALLS_TABLE" ]; then
    echo "SUCCESS: $CALLS_TABLE ($(wc -l < "$CALLS_TABLE") lines)"
else
    echo "ERROR: Output file was not created: $CALLS_TABLE"
    exit 1
fi

echo "Completed within-sample UMR calls table at $(date)"
