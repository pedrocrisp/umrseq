#!/bin/bash -l
#SBATCH --job-name recombine_bw
#SBATCH --requeue
#SBATCH --partition=general

########## Recombine BigWig Chromosomes #################
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

# Load required modules
# requires bigWigToBedGraph and bedGraphToBigWig to be in path
# requires python 3 with pandas installed in the conda environment
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
OUTPUT_FILE="${OUTPUT_DIR}/${SAMPLE_PREFIX}${SUFFIX}"

echo "Input file: $INPUT_FILE"
echo "Output file: $OUTPUT_FILE"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    exit 1
fi

# Check if conversion table exists
if [ ! -f "$CONVERSION_TABLE" ]; then
    echo "ERROR: Conversion table not found: $CONVERSION_TABLE"
    exit 1
fi

########## Run #################

echo "Starting chromosome recombination for $SAMPLE_PREFIX at $(date)"

# Run the Python script from the script directory (SCRIPT_DIR, passed from the _sbatch.sh runner)
python ${SCRIPT_DIR}/recombine_bigwig.py \
    "$INPUT_FILE" \
    "$CONVERSION_TABLE" \
    "$OUTPUT_FILE" \
    "$SAMPLE_PREFIX" \
    "$OUTPUT_DIR"

# Check if output was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    echo "SUCCESS: Output file created: $OUTPUT_FILE"
    
    # Get file sizes for comparison
    input_size=$(du -h "$INPUT_FILE" | cut -f1)
    output_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    
    echo "Input file size: $input_size"
    echo "Output file size: $output_size"
else
    echo "ERROR: Output file was not created: $OUTPUT_FILE"
    exit 1
fi

echo "Completed chromosome recombination for $SAMPLE_PREFIX at $(date)"
