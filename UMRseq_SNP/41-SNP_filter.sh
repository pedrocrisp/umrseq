#!/bin/bash -l
#SBATCH --job-name 41-SNP_filter
#SBATCH --requeue
#SBATCH --partition=general

########## UMR-seq SNP calling - Step 2: per-region SNP filtering (bcftools) #################
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

INPUT_VCF="${INPUT_DIR}/${REGION}.raw.vcf.gz"
OUTPUT_VCF="${OUTPUT_DIR}/${REGION}.filtered.vcf.gz"

echo "Input file: $INPUT_VCF"
echo "Output file: $OUTPUT_VCF"
echo "Max missing: $MAX_MISSING"
echo "Min MAF: $MIN_MAF"

if [ ! -f "$INPUT_VCF" ]; then
    echo "ERROR: Input VCF not found: $INPUT_VCF"
    exit 1
fi

########## Run #################

echo "Starting SNP filtering for $REGION at $(date)"

# filter
# -e "F_MISSING > x"   exclude sites where more than x of samples have a missing genotype
# view
# -q x:minor           min minor allele frequency
# -m2 -M2              biallelic sites only
# -v snps              SNPs only
bcftools filter -e "F_MISSING > ${MAX_MISSING}" -Ou "$INPUT_VCF" | \
bcftools view -q ${MIN_MAF}:minor -m2 -M2 -v snps -Oz -o "$OUTPUT_VCF"
bcftools index "$OUTPUT_VCF"

########## Check outputs #################

if [ -f "$OUTPUT_VCF" ]; then
    echo "SUCCESS: Output file created: $OUTPUT_VCF"
    echo "Sites before filtering: $(bcftools index -n "$INPUT_VCF")"
    echo "Sites after filtering: $(bcftools index -n "$OUTPUT_VCF")"
else
    echo "ERROR: Output file was not created: $OUTPUT_VCF"
    exit 1
fi

echo "Completed SNP filtering for $REGION at $(date)"
