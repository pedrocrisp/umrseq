#!/bin/bash -l
#SBATCH --job-name 22-UMR_featurecounts
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - Step 3: per-sample read support (featureCounts) #################
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

# featureCounts (subread) must be available in $conda_enviro above, or via a
# module load below - adjust for your cluster, e.g.:
# module load subread/2.0.3

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

OUTPUT_FILE="${OUTPUT_DIR}/${SAMPLE_PREFIX}.featurecounts.counts"

echo "BAM file: $BAM_FILE"
echo "SAF file: $SAF_FILE"
echo "Output file: $OUTPUT_FILE"

if [ ! -f "$SAF_FILE" ]; then
    echo "ERROR: SAF file not found: $SAF_FILE"
    exit 1
fi

########## Run #################

echo "Starting featureCounts for $SAMPLE_PREFIX at $(date)"

# -F SAF      annotation is in SAF format
# -p          paired end
# -B          only count read pairs (frags) if both reads mapped
# -C          don't count chimeric frags
# -P          check frag length
# -d 50       min frag length 50bp
# -D 1000     max frag length 1000bp
# -Q 10       min map quality
featureCounts -F SAF -p -C -B -P -d 50 -D 1000 -Q 10 \
    -a "$SAF_FILE" \
    -o "$OUTPUT_FILE" \
    "$BAM_FILE"

# Check if output was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    echo "SUCCESS: Output file created: $OUTPUT_FILE"
    output_lines=$(wc -l < "$OUTPUT_FILE")
    echo "Output lines: $output_lines"
else
    echo "ERROR: Output file was not created: $OUTPUT_FILE"
    exit 1
fi

echo "Completed featureCounts for $SAMPLE_PREFIX at $(date)"
