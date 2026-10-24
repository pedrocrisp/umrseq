#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 42-SNP_merge_sbatch.sh <regions_list.txt> <input_dir> <output_dir> <out_prefix> <max_het_frac> <min_hom_alt_frac> <min_hom_ref_frac> <walltime> <memory> <account_department>

Example:
bash 42-SNP_merge_sbatch.sh regions.txt ./snps_filtered ./snps_merged all_samples 0.1 0.05 0.05 4:00:00 8 AccountString

Arguments:
  regions_list.txt    - Same regions list used for steps 1-2. Regions are merged in this order
  input_dir           - Directory containing the '<region>.filtered.vcf.gz' files from step 2 (step 2's output_dir)
  output_dir          - Directory for the merged VCF files
  out_prefix          - Prefix used to name the output files (e.g., all_samples)
  max_het_frac        - Het filter: keep sites where het (0/1) calls are below this fraction of samples
                         (suggested: 0.1)
  min_hom_alt_frac    - Het filter: keep sites where hom-alt (1/1) calls are above this fraction of samples
                         (suggested: 0.05)
  min_hom_ref_frac    - Het filter: keep sites where hom-ref (0/0) calls are above this fraction of samples
                         (suggested: 0.05)
                         Sites must also have more hom-alt than het calls. Fractions are of all samples,
                         including missing genotypes
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  account_department  - SLURM account/department name

This is step 3 of the UMR-seq SNP calling module: it concatenates every
region's filtered SNPs into one VCF, then removes sites with too many
heterozygous calls (42-SNP_remove_hets.py). Single job (not an array). Only
run this once every step 2 array task has completed successfully."

#define step in the pipeline - should be the same name as the script
step=42-SNP_merge

######### Setup ################
regions_list=$1
input_dir=$2
output_dir=$3
out_prefix=$4
max_het_frac=$5
min_hom_alt_frac=$6
min_hom_ref_frac=$7
walltime=$8
mem=$9
account_department=${10}

if [ "$#" -lt "10" ]
then
echo "$usage"
exit -1
else
echo "Merging filtered SNPs for regions listed in '$regions_list'"
echo "Input directory: '$input_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
echo "Het filter: max het frac '$max_het_frac', min hom-alt frac '$min_hom_alt_frac', min hom-ref frac '$min_hom_ref_frac'"
fi

#check inputs exist
if [ ! -f "$regions_list" ]; then
    echo "ERROR: Regions list not found: $regions_list"
    exit -1
fi
if [ ! -d "$input_dir" ]; then
    echo "ERROR: Input directory not found: $input_dir"
    exit -1
fi

#find script to run, makes it file system agnostic
if
[[ $OSTYPE == darwin* ]]
then
readlink=$(which greadlink)
scriptdir="$(dirname $($readlink -f $0))"
else
scriptdir="$(dirname $(readlink -f $0))"
fi

########## Run #################

#make log folders
#make logs folder if it doesnt exist yet
mkdir -p logs

timestamp=$(date +%Y%m%d-%H%M%S)

#make output dir if it doesnt exist yet
mkdir -p $output_dir

#make logs folder, timestamped
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

#script path and cat a record of what was run
script_to_sbatch=${scriptdir}/${step}.sh
cat $script_to_sbatch > ${log_folder}/script.log
cat $0 > ${log_folder}/sbatch_runner.log
cp $regions_list ${log_folder}/regions_list.txt

#submit sbatch (single job, no array - this step needs every region's output at once)
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the dir structures
sbatch \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export REGIONS_LIST=${regions_list},INPUT_DIR=${input_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix},MAX_HET_FRAC=${max_het_frac},MIN_HOM_ALT_FRAC=${min_hom_alt_frac},MIN_HOM_REF_FRAC=${min_hom_ref_frac},SCRIPT_DIR=${scriptdir} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue --me"
echo "Check logs in: $log_folder"
