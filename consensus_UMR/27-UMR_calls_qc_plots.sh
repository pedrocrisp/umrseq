#!/bin/bash -l
#SBATCH --job-name 27-UMR_calls_qc_plots
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Calling - Optional: QC plots for a random subset of calls #################
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

########## Set up sample #################

mkdir -p $OUTPUT_DIR
PLOT_DIR="${OUTPUT_DIR}/plots"
mkdir -p "$PLOT_DIR"

SAMPLED_IDS="${OUTPUT_DIR}/qc_sample.umr_ids.txt"
QC_CPM="${OUTPUT_DIR}/qc_sample.cpm.tsv"

if [ ! -f "$CALLS_TABLE" ]; then
    echo "ERROR: Calls table not found: $CALLS_TABLE"
    exit 1
fi
if [ ! -f "$CPM_MATRIX" ]; then
    echo "ERROR: CPM matrix not found: $CPM_MATRIX"
    exit 1
fi

########## Run #################

echo "Sampling $N_UMRS random called UMR(s) at $(date)"
# head truncating shuf's output makes shuf exit on SIGPIPE (141); that's
# expected once head has the lines it needs, so don't let pipefail trip on it
( set +o pipefail
  grep -v "^UMR_ID" "$CALLS_TABLE" | cut -f1 | shuf | head -n "$N_UMRS"
) > "$SAMPLED_IDS"

echo "Extracting their CPM rows at $(date)"
{ head -n 1 "$CPM_MATRIX"; LC_ALL=C fgrep -f "$SAMPLED_IDS" "$CPM_MATRIX"; } > "$QC_CPM"

echo "Generating diagnostic plots at $(date)"
# Run the Python script from the script directory (SCRIPT_DIR, passed from the _sbatch.sh runner)
python ${SCRIPT_DIR}/25-UMR_calls.py \
    "$QC_CPM" \
    "$OUTPUT_DIR" \
    --plots "$PLOT_DIR"

########## Check outputs #################

png_count=$(find "$PLOT_DIR" -name '*.png' | wc -l)
echo "SUCCESS: wrote $png_count plot(s) to $PLOT_DIR"

echo "Completed UMR calls QC plots at $(date)"
