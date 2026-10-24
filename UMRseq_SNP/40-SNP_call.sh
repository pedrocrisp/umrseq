#!/bin/bash -l
#SBATCH --job-name 40-SNP_call
#SBATCH --requeue
#SBATCH --partition=general

########## UMR-seq SNP calling - Step 1: per-region joint SNP calling (bcftools) #################
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

module load bcftools/1.22-gcc-14.2.0

########## Set up region #################

#get region from list
#use sed, -n suppression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID}
REGION="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${REGIONS_LIST})"

echo "Processing region: $REGION"

mkdir -p $OUTPUT_DIR

TMP_VCF="${OUTPUT_DIR}/${REGION}.raw.tmp.vcf.gz"
TMP_RENAMED_VCF="${OUTPUT_DIR}/${REGION}.raw.tmp.renamed.vcf.gz"
OUTPUT_VCF="${OUTPUT_DIR}/${REGION}.raw.vcf.gz"

echo "BAM list: $BAM_LIST"
echo "Reference: $REFERENCE"
echo "Output file: $OUTPUT_VCF"

########## Run #################

echo "Starting SNP calling for $REGION at $(date)"

# mpileup (all samples jointly, one region)
# --skip-indels   SNPs only
# --min-MQ 10     min mapping quality, matches the 02-bowtie2 MAPQ filter
# -a              also record per-sample allele depth (AD) and read depth (DP)
# -r              only this region (needs indexed BAMs)
# -b              list of BAM files, one per sample
# call
# --ploidy 2      diploid model (for polyploids, e.g. wheat, each subgenome is called as diploid)
# -m              multiallelic caller
# -v              output variant sites only
bcftools mpileup \
    --fasta-ref "$REFERENCE" \
    --skip-indels \
    --min-MQ 10 \
    -a FORMAT/AD,FORMAT/DP \
    -r "$REGION" \
    -b "$BAM_LIST" \
    -Ou | \
bcftools call --ploidy 2 -mv -Oz -o "$TMP_VCF"

# BAMs from 02-bowtie2 have no read groups, so mpileup names each sample by its
# BAM path - rename to the sample prefixes (same order as BAM_LIST)
n_vcf_samples=$(bcftools query -l "$TMP_VCF" | wc -l)
n_names=$(wc -l < "$SAMPLE_NAMES")
if [ "$n_vcf_samples" -ne "$n_names" ]; then
    echo "ERROR: VCF has $n_vcf_samples samples but $SAMPLE_NAMES has $n_names names"
    echo "(BAMs with read groups sharing an SM tag are merged by mpileup - check the BAM headers)"
    exit 1
fi
bcftools reheader -s "$SAMPLE_NAMES" -o "$TMP_RENAMED_VCF" "$TMP_VCF"

bcftools sort --temp-dir "${OUTPUT_DIR}/sort_tmp_${REGION}" "$TMP_RENAMED_VCF" -Oz -o "$OUTPUT_VCF"
bcftools index "$OUTPUT_VCF"

rm -v "$TMP_VCF" "$TMP_RENAMED_VCF"

########## Check outputs #################

if [ -f "$OUTPUT_VCF" ]; then
    echo "SUCCESS: Output file created: $OUTPUT_VCF"
    echo "Variant sites: $(bcftools index -n "$OUTPUT_VCF")"
else
    echo "ERROR: Output file was not created: $OUTPUT_VCF"
    exit 1
fi

echo "Completed SNP calling for $REGION at $(date)"
