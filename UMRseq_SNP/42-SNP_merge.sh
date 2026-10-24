#!/bin/bash -l
#SBATCH --job-name 42-SNP_merge
#SBATCH --requeue
#SBATCH --partition=general

########## UMR-seq SNP calling - Step 3: merge regions and remove het sites #################
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

module load bcftools/1.22-gcc-14.2.0
# python3 (3.6+, any on PATH) for 42-SNP_remove_hets.py

########## Set up cohort #################

mkdir -p $OUTPUT_DIR

VCF_FILE_LIST="${OUTPUT_DIR}/${OUT_PREFIX}.filtered_vcf_list.txt"
MERGED_VCF="${OUTPUT_DIR}/${OUT_PREFIX}.snps.vcf.gz"
NOHET_VCF="${OUTPUT_DIR}/${OUT_PREFIX}.snps.nohet.vcf.gz"

# list every region's filtered VCF, in regions list order (bcftools concat
# needs the regions in the same order as the VCF header contigs)
: > "$VCF_FILE_LIST"
while IFS= read -r region || [[ -n "$region" ]]; do
    [[ -z "$region" ]] && continue
    region_vcf="${INPUT_DIR}/${region}.filtered.vcf.gz"
    if [ ! -f "$region_vcf" ]; then
        echo "ERROR: Filtered VCF not found for region $region: $region_vcf"
        exit 1
    fi
    echo "$region_vcf" >> "$VCF_FILE_LIST"
done < "$REGIONS_LIST"

echo "Number of region VCFs to merge: $(wc -l < "$VCF_FILE_LIST")"

########## Run #################

echo "Merging filtered SNPs at $(date)"

bcftools concat -f "$VCF_FILE_LIST" -Oz -o "$MERGED_VCF"
bcftools index "$MERGED_VCF"

echo "Removing het sites at $(date)"

# keeps sites where hom-alt > het calls, and (as fractions of all samples):
# --max-het-frac       het calls below this      (suggested: 0.1)
# --min-hom-alt-frac   hom-alt calls above this  (suggested: 0.05)
# --min-hom-ref-frac   hom-ref calls above this  (suggested: 0.05)
# thresholds are passed from 42-SNP_merge_sbatch.sh
echo "Het filter: max het frac $MAX_HET_FRAC, min hom-alt frac $MIN_HOM_ALT_FRAC, min hom-ref frac $MIN_HOM_REF_FRAC"
bcftools view "$MERGED_VCF" | \
python3 ${SCRIPT_DIR}/42-SNP_remove_hets.py - \
    --max-het-frac $MAX_HET_FRAC \
    --min-hom-alt-frac $MIN_HOM_ALT_FRAC \
    --min-hom-ref-frac $MIN_HOM_REF_FRAC | \
bcftools view -Oz -o "$NOHET_VCF" -
bcftools index "$NOHET_VCF"

########## Check outputs #################

for f in "$MERGED_VCF" "$NOHET_VCF"; do
    if [ -f "$f" ]; then
        echo "SUCCESS: $f ($(bcftools index -n "$f") SNPs)"
    else
        echo "ERROR: Output file was not created: $f"
        exit 1
    fi
done

echo "Completed SNP merge at $(date)"
