#!/bin/bash -l
#SBATCH --job-name 20-EPIC2_reformat
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - Step 1: per-sample ID assignment #################
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
echo "File suffix: $SUFFIX"

# create output folder if it does not exist
mkdir -p $OUTPUT_DIR

# Construct full filenames
INPUT_FILE="${INPUT_DIR}/${SAMPLE_PREFIX}${SUFFIX}"
OUTPUT_FILE="${OUTPUT_DIR}/${SAMPLE_PREFIX}${SUFFIX}.names"

echo "Input file: $INPUT_FILE"
echo "Output file: $OUTPUT_FILE"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    exit 1
fi

########## Run #################

echo "Starting UMR ID assignment for $SAMPLE_PREFIX at $(date)"

# Run the Python script from the script directory (SCRIPT_DIR, passed from the _sbatch.sh runner)
python ${SCRIPT_DIR}/20-EPIC2_reformat.py \
    "$INPUT_FILE" \
    "$OUTPUT_FILE" \
    "$SAMPLE_PREFIX"

# Check if output was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    echo "SUCCESS: Output file created: $OUTPUT_FILE"

    input_lines=$(wc -l < "$INPUT_FILE")
    output_lines=$(wc -l < "$OUTPUT_FILE")

    echo "Input lines: $input_lines"
    echo "Output lines: $output_lines"
else
    echo "ERROR: Output file was not created: $OUTPUT_FILE"
    exit 1
fi

echo "Completed UMR ID assignment for $SAMPLE_PREFIX at $(date)"

conda deactivate
