#!/bin/bash -l
#SBATCH --job-name 25-UMR_calls
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Calling - Step 2: per-batch presence/absence calling #################
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

########## Set up batch #################

#get batch file path from the list
#use sed, -n suppression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID}
BATCH_FILE="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo "Processing batch: $BATCH_FILE"

mkdir -p $OUTPUT_DIR

if [ ! -f "$BATCH_FILE" ]; then
    echo "ERROR: Batch file not found: $BATCH_FILE"
    exit 1
fi

########## Run #################

echo "Starting UMR calling for $BATCH_FILE at $(date)"

# Run the Python script from the git repository folder (note: this location is hard coded)
python ~/gitrepos/AI_code_dev_testing/25-UMR_calls.py \
    "$BATCH_FILE" \
    "$OUTPUT_DIR"

BATCH_ID="$(basename "$BATCH_FILE")"
BATCH_ID="${BATCH_ID%.*}"
CALLS_FILE="${OUTPUT_DIR}/${BATCH_ID}.calls"

if [ -f "$CALLS_FILE" ]; then
    echo "SUCCESS: Output file created: $CALLS_FILE"
    echo "Output lines: $(wc -l < "$CALLS_FILE")"
else
    echo "ERROR: Output file was not created: $CALLS_FILE"
    exit 1
fi

echo "Completed UMR calling for $BATCH_FILE at $(date)"
