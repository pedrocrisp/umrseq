#!/bin/bash -l
#SBATCH --job-name 33-UMR_coverage
#SBATCH --requeue
#SBATCH --partition=general

########## Within-sample UMR Calling - Step 1: per-sample UMR coverage (mosdepth) #################
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

# mosdepth must be available in $conda_enviro above, or via a module load
# below - adjust for your cluster, e.g.:
# module load mosdepth/0.3.8

########## Set up sample #################

#get sample prefix from list
#use sed, -n suppression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID}
SAMPLE_PREFIX="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo "Processing sample: $SAMPLE_PREFIX"
echo "File suffix: $SUFFIX"

# create output folder if it does not exist
mkdir -p $OUTPUT_DIR

# BAM filenames may have extra text between the sample prefix and the suffix
# (e.g. a cultivar name), so match by glob rather than exact concatenation
BAM_MATCHES=("${INPUT_DIR}/${SAMPLE_PREFIX}"*"${SUFFIX}")

if [ ! -e "${BAM_MATCHES[0]}" ]; then
    echo "ERROR: No BAM file found matching ${INPUT_DIR}/${SAMPLE_PREFIX}*${SUFFIX}"
    exit 1
fi
if [ "${#BAM_MATCHES[@]}" -ne 1 ]; then
    echo "ERROR: Expected exactly one BAM file matching ${INPUT_DIR}/${SAMPLE_PREFIX}*${SUFFIX}, found ${#BAM_MATCHES[@]}:"
    printf '%s\n' "${BAM_MATCHES[@]}"
    exit 1
fi
BAM_FILE="${BAM_MATCHES[0]}"

# mosdepth requires an index alongside the BAM
if [ ! -f "${BAM_FILE}.bai" ] && [ ! -f "${BAM_FILE}.csi" ]; then
    echo "ERROR: No index found for $BAM_FILE (expected ${BAM_FILE}.bai or ${BAM_FILE}.csi)"
    exit 1
fi

OUTPUT_PREFIX="${OUTPUT_DIR}/${SAMPLE_PREFIX}"
REGIONS_FILE="${OUTPUT_PREFIX}.regions.bed.gz"

echo "BAM file: $BAM_FILE"
echo "Consensus BED: $CONSENSUS_BED"
echo "Output prefix: $OUTPUT_PREFIX"

if [ ! -f "$CONSENSUS_BED" ]; then
    echo "ERROR: Consensus BED file not found: $CONSENSUS_BED"
    exit 1
fi

########## Run #################

echo "Starting mosdepth for $SAMPLE_PREFIX at $(date)"

# -x       fast mode (skip per-base depth, only region means are needed here)
# -Q 10    min map quality
# -b       consensus UMR intervals to compute mean depth over
mosdepth -x -Q 10 -b "$CONSENSUS_BED" "$OUTPUT_PREFIX" "$BAM_FILE"

# Check if output was created successfully
if [ -f "$REGIONS_FILE" ]; then
    echo "SUCCESS: Output file created: $REGIONS_FILE"
    region_count=$(zcat "$REGIONS_FILE" | wc -l)
    echo "Regions: $region_count"
else
    echo "ERROR: Output file was not created: $REGIONS_FILE"
    exit 1
fi

echo "Completed mosdepth for $SAMPLE_PREFIX at $(date)"
