#!/bin/bash -l
#SBATCH --job-name 21-UMR_merge
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - Step 2: cohort merge #################
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

# bedtools must be available either in $conda_enviro above, or via a module
# load below - adjust for your cluster, e.g.:
module load bedtools/2.30.0-gcc-11.3.0

########## Set up cohort #################

mkdir -p $OUTPUT_DIR

ALL_UMR_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.bed"
MERGED_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.bed"
CONSENSUS_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.bed"
CONSENSUS_FMT_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.fmt.bed"
CONSENSUS_NOALT_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.noALT.bed"
CONSENSUS_NOALT_SAF="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.noALT.saf"
CONSENSUS_BIN_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.${BIN_SIZE}.bed"
CONSENSUS_NOALT_BIN_BED="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.noALT.${BIN_SIZE}.bed"
CONSENSUS_NOALT_BIN_SAF="${OUTPUT_DIR}/${OUT_PREFIX}.umr.merged.consensus.noALT.${BIN_SIZE}.saf"

# Check that every sample's per-UMR ".names" file from step 1 is present
NAMES_FILES=()
while IFS= read -r SAMPLE_PREFIX; do
    [ -z "$SAMPLE_PREFIX" ] && continue
    NAMES_FILE="${NAMES_DIR}/${SAMPLE_PREFIX}${SUFFIX}.names"
    if [ ! -f "$NAMES_FILE" ]; then
        echo "ERROR: Names file not found (did step 1 finish for this sample?): $NAMES_FILE"
        exit 1
    fi
    NAMES_FILES+=("$NAMES_FILE")
done < "$LIST"

echo "Found ${#NAMES_FILES[@]} per-sample names files"

########## Run #################

echo "Concatenating and sorting per-sample UMRs at $(date)"
# LC_COLLATE=C for case-sensitive sort, required for bedtools merge to agree
# with the genome's chromosome sort order
LC_COLLATE=C sort -k1,1 -k2,2n "${NAMES_FILES[@]}" > "$ALL_UMR_BED"

echo "Merging overlapping UMRs across samples at $(date)"
bedtools merge -i "$ALL_UMR_BED" -c 4 -o collapse -delim "|" > "$MERGED_BED"

echo "Building cohort consensus UMRs at $(date)"
python ~/gitrepos/AI_code_dev_testing/21-UMR_consensus_merge.py \
    "$ALL_UMR_BED" \
    "$MERGED_BED" \
    > "$CONSENSUS_BED"

echo "Formatting consensus outputs at $(date)"
grep -v "^#" "$CONSENSUS_BED" | cut -f 1-3 \
    | awk -v name="${OUT_PREFIX}.consensus" '{print $1"\t"$2"\t"$3"\t"name}' \
    | LC_COLLATE=C sort -k1,1 -k2,2n \
    > "$CONSENSUS_FMT_BED"

grep -v "ALT_" "$CONSENSUS_BED" | cut -f 1-4 > "$CONSENSUS_NOALT_BED"

echo "Converting consensus UMRs to SAF for featureCounts at $(date)"
# SAF format: GeneID, Chr, Start (1-based), End, Strand
awk 'BEGIN{OFS="\t"} {print $4, $1, $2+1, $3, "."}' "$CONSENSUS_NOALT_BED" > "$CONSENSUS_NOALT_SAF"

echo "Splitting consensus UMRs into ${BIN_SIZE}bp sub-bins at $(date)"
# Run the Python script from the git repository folder (note: this location is hard coded)
python ~/gitrepos/AI_code_dev_testing/21-UMR_consensus_bin.py \
    "$CONSENSUS_BED" \
    "$CONSENSUS_BIN_BED" \
    "$BIN_SIZE"

python ~/gitrepos/AI_code_dev_testing/21-UMR_consensus_bin.py \
    "$CONSENSUS_NOALT_BED" \
    "$CONSENSUS_NOALT_BIN_BED" \
    "$BIN_SIZE"

echo "Converting binned consensus UMRs to SAF for featureCounts at $(date)"
awk 'BEGIN{OFS="\t"} {print $4, $1, $2+1, $3, "."}' "$CONSENSUS_NOALT_BIN_BED" > "$CONSENSUS_NOALT_BIN_SAF"

########## Check outputs #################

for f in "$ALL_UMR_BED" "$MERGED_BED" "$CONSENSUS_BED" "$CONSENSUS_FMT_BED" "$CONSENSUS_NOALT_BED" "$CONSENSUS_NOALT_SAF" "$CONSENSUS_BIN_BED" "$CONSENSUS_NOALT_BIN_BED" "$CONSENSUS_NOALT_BIN_SAF"; do
    if [ -f "$f" ]; then
        echo "SUCCESS: $f ($(wc -l < "$f") lines)"
    else
        echo "ERROR: Output file was not created: $f"
        exit 1
    fi
done

echo "Completed UMR cohort consensus at $(date)"
