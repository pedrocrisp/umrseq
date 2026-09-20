#!/bin/bash -l
#SBATCH --job-name 26-UMR_calls_table
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Calling - Step 3: aggregate batches into final call table #################
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

########## Set up cohort #################

mkdir -p $OUTPUT_DIR

CALLS_TABLE="${OUTPUT_DIR}/${OUT_PREFIX}.UMR.calls.tsv"
BODY_FILE="${OUTPUT_DIR}/.calls_body.txt"

# Check that every batch's '.calls' file from step 2 is present
CALLS_FILES=()
while IFS= read -r BATCH_FILE; do
    [ -z "$BATCH_FILE" ] && continue
    BATCH_ID="$(basename "$BATCH_FILE")"
    BATCH_ID="${BATCH_ID%.*}"
    CALLS_FILE="${CALLS_DIR}/${BATCH_ID}.calls"
    if [ ! -f "$CALLS_FILE" ]; then
        echo "ERROR: Calls file not found (did step 2 finish for this batch?): $CALLS_FILE"
        exit 1
    fi
    CALLS_FILES+=("$CALLS_FILE")
done < "$BATCH_LIST"

echo "Found ${#CALLS_FILES[@]} per-batch calls files"

########## Run #################

echo "Building header from sample list at $(date)"
# Column order must match how 24-UMR_combine_calls.sh built the counts
# matrix: UMR_ID followed by samples in sample_list.txt order
{
    printf "UMR_ID"
    while IFS= read -r SAMPLE_PREFIX; do
        [ -z "$SAMPLE_PREFIX" ] && continue
        printf "\t%s" "$SAMPLE_PREFIX"
    done < "$SAMPLE_LIST"
    printf "\n"
} > "${OUTPUT_DIR}/.header.txt"

echo "Aggregating per-batch calls at $(date)"
cat "${CALLS_FILES[@]}" | grep -v "^UMR_ID" | LC_COLLATE=C sort -k1,1 \
    | sed 's/YES/1/g; s/NO/0/g' \
    > "$BODY_FILE"

cat "${OUTPUT_DIR}/.header.txt" "$BODY_FILE" > "$CALLS_TABLE"
rm -f "${OUTPUT_DIR}/.header.txt" "$BODY_FILE"

########## Check outputs #################

if [ -f "$CALLS_TABLE" ]; then
    echo "SUCCESS: $CALLS_TABLE ($(wc -l < "$CALLS_TABLE") lines)"
else
    echo "ERROR: Output file was not created: $CALLS_TABLE"
    exit 1
fi

echo "Completed UMR calls table at $(date)"
