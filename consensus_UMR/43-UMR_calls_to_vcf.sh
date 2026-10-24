#!/bin/bash -l
#SBATCH --job-name 43-UMR_calls_to_vcf
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - optional: convert UMR call table to VCF #################
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

########## Set up #################

mkdir -p $OUTPUT_DIR

OUTPUT_VCF="${OUTPUT_DIR}/$(basename "$CALLS_TABLE" .tsv).vcf"

echo "Calls table: $CALLS_TABLE"
echo "Output file: $OUTPUT_VCF"

########## Run #################

echo "Converting UMR calls to VCF at $(date)"

python3 ${SCRIPT_DIR}/43-UMR_calls_to_vcf.py "$CALLS_TABLE" > "$OUTPUT_VCF"

########## Check outputs #################

if [ -s "$OUTPUT_VCF" ]; then
    echo "SUCCESS: $OUTPUT_VCF ($(grep -vc '^#' "$OUTPUT_VCF") UMRs)"
else
    echo "ERROR: Output file was not created: $OUTPUT_VCF"
    exit 1
fi

echo "Completed UMR calls to VCF at $(date)"
