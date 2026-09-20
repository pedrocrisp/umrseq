#!/bin/bash -l
#SBATCH --job-name 34-UMR_within_sample_calls
#SBATCH --requeue
#SBATCH --partition=general

########## Within-sample UMR Calling - Step 2: per-sample presence/absence calling #################
set -xeuo pipefail

echo ------------------------------------------------------
echo SBATCH: working directory is $SLURM_SUBMIT_DIR
echo SBATCH: job identifier is $SLURM_JOBID
echo SBATCH: array_ID is ${SLURM_ARRAY_TASK_ID}
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

########## Set up sample #################

#get sample prefix from list
#use sed, -n suppression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID}
SAMPLE_PREFIX="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo "Processing sample: $SAMPLE_PREFIX"

mkdir -p $OUTPUT_DIR
PLOT_DIR="${OUTPUT_DIR}/plots"
mkdir -p "$PLOT_DIR"

REGIONS_GZ="${COVERAGE_DIR}/${SAMPLE_PREFIX}.regions.bed.gz"

if [ ! -f "$REGIONS_GZ" ]; then
    echo "ERROR: Regions file not found (did step 1 finish for this sample?): $REGIONS_GZ"
    exit 1
fi

########## Run #################

echo "Starting within-sample UMR calling for $SAMPLE_PREFIX at $(date)"

# Run the Python script from the git repository folder (note: this location is hard coded)
python ~/gitrepos/AI_code_dev_testing/34-UMR_within_sample_calls.py \
    "$REGIONS_GZ" \
    "$SAMPLE_PREFIX" \
    "$OUTPUT_DIR" \
    --shift "$SHIFT" \
    --bw "$BW" \
    --plots "$PLOT_DIR"

CALLS_FILE="${OUTPUT_DIR}/${SAMPLE_PREFIX}.coverage.calls.tsv"

# A sample whose coverage distribution isn't bimodal produces no calls file -
# this is an expected outcome (not every sample's depth distribution splits
# cleanly into present/absent), so it's a warning, not a job failure
if [ -f "$CALLS_FILE" ]; then
    echo "SUCCESS: Output file created: $CALLS_FILE"
    echo "Output lines: $(wc -l < "$CALLS_FILE")"
else
    echo "WARNING: No calls file produced for $SAMPLE_PREFIX (coverage distribution was not bimodal) - see ${OUTPUT_DIR}/${SAMPLE_PREFIX}.coverage.stats.txt and ${PLOT_DIR}/${SAMPLE_PREFIX}.plot1.bi.pdf / plot2.bi.pdf"
fi

echo "Completed within-sample UMR calling for $SAMPLE_PREFIX at $(date)"
