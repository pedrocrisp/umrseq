#!/bin/bash -l
#SBATCH --job-name 21b-UMR_consensus_merge_background
#SBATCH --requeue
#SBATCH --partition=general

########## UMR Consensus - Step 2b (optional): random background regions #################
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

########## Set up #################

mkdir -p $OUTPUT_DIR

# Output files are named after the input consensus BED, not a separate
# prefix, so binned and whole-UMR runs (different consensus_bed inputs)
# never clash in the same output_dir
CONSENSUS_BASENAME="$(basename "$CONSENSUS_BED" .bed)"

SUBSAMPLE_BED="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.subsample_for_background.bed"
SHUFFLED_BED="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.background.shuffled.bed"
BACKGROUND_BED="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.background.bed"
BACKGROUND_SAF="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.background.saf"
MERGED_BED="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.umr_plus_background.bed"
MERGED_SAF="${OUTPUT_DIR}/${CONSENSUS_BASENAME}.umr_plus_background.saf"

########## Run #################

TOTAL_UMRS=$(wc -l < "$CONSENSUS_BED")
N_BACKGROUND=$(awk -v f="$BACKGROUND_FRACTION" -v n="$TOTAL_UMRS" 'BEGIN{printf "%d", (n*f)+0.5}')

if [ "$N_BACKGROUND" -lt 1 ]; then
    echo "ERROR: background_fraction '$BACKGROUND_FRACTION' of $TOTAL_UMRS UMRs rounds to 0 background regions"
    exit 1
fi
if [ "$N_BACKGROUND" -gt "$TOTAL_UMRS" ]; then
    echo "ERROR: background_fraction must be <= 1.0 (requested $N_BACKGROUND background regions from $TOTAL_UMRS UMRs)"
    exit 1
fi

echo "Sampling $N_BACKGROUND of $TOTAL_UMRS UMRs (fraction $BACKGROUND_FRACTION) as the background length template at $(date)"

# Seeded random subsample without replacement: tag each line with a seeded
# random number, sort numerically on it, then take the top N - a portable
# alternative to 'shuf --random-source', which isn't available on macOS

# 'head' exits as soon as it has its N lines, closing the pipe early; with a
# small N_BACKGROUND this makes 'sort'/'cut' get SIGPIPE (exit 141) while
# still writing, which 'pipefail' would otherwise treat as a real failure
# even though the output is correct - disable it for just this pipeline
set +o pipefail
awk -v seed="$SEED" 'BEGIN{srand(seed)} {print rand()"\t"$0}' "$CONSENSUS_BED" \
    | sort -k1,1g \
    | cut -f2- \
    | head -n "$N_BACKGROUND" \
    > "$SUBSAMPLE_BED"
set -o pipefail

echo "Shuffling subsampled regions to random non-UMR-overlapping locations at $(date)"
# -noOverlapping: background regions don't overlap each other either
# -excl: background regions can't land on an existing consensus UMR
bedtools shuffle \
    -i "$SUBSAMPLE_BED" \
    -g "$GENOME_FILE" \
    -excl "$CONSENSUS_BED" \
    -noOverlapping \
    -maxTries 10000 \
    -seed "$SEED" \
    > "$SHUFFLED_BED"

echo "Assigning unique background region IDs at $(date)"
# LC_COLLATE=C for case-sensitive sort, required to agree with the genome's
# chromosome sort order (matches step 2's convention)
LC_COLLATE=C sort -k1,1 -k2,2n "$SHUFFLED_BED" \
    | awk 'BEGIN{OFS="\t"} {printf "%s\t%s\t%s\tBG_%09d\n", $1, $2, $3, NR}' \
    > "$BACKGROUND_BED"

echo "Converting background regions to SAF for featureCounts at $(date)"
# SAF format: GeneID, Chr, Start (1-based), End, Strand
awk 'BEGIN{OFS="\t"} {print $4, $1, $2+1, $3, "."}' "$BACKGROUND_BED" > "$BACKGROUND_SAF"

echo "Combining UMR consensus and background regions at $(date)"
cat "$CONSENSUS_BED" "$BACKGROUND_BED" | LC_COLLATE=C sort -k1,1 -k2,2n > "$MERGED_BED"
awk 'BEGIN{OFS="\t"} {print $4, $1, $2+1, $3, "."}' "$MERGED_BED" > "$MERGED_SAF"

########## Check outputs #################

for f in "$SUBSAMPLE_BED" "$SHUFFLED_BED" "$BACKGROUND_BED" "$BACKGROUND_SAF" "$MERGED_BED" "$MERGED_SAF"; do
    if [ -f "$f" ]; then
        echo "SUCCESS: $f ($(wc -l < "$f") lines)"
    else
        echo "ERROR: Output file was not created: $f"
        exit 1
    fi
done

echo "Completed background region generation at $(date)"
