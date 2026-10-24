#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 41-SNP_filter_sbatch.sh <regions_list.txt> <input_dir> <output_dir> <max_missing> <min_maf> <walltime> <memory> <account_department>

Example:
bash 41-SNP_filter_sbatch.sh regions.txt ./snps_raw ./snps_filtered 0.1 0.05 2:00:00 8 AccountString

Arguments:
  regions_list.txt    - Same regions list used for step 1 (40-SNP_call), one array task per line
  input_dir           - Directory containing the '<region>.raw.vcf.gz' files from step 1 (step 1's output_dir)
  output_dir          - Directory for per-region filtered VCF files
  max_missing         - Remove sites where more than this fraction of samples have a missing genotype
                         (e.g. 0.1 = keep sites called in at least 90% of samples)
  min_maf             - Minimum minor allele frequency to keep a site (e.g. 0.05)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB per job
  account_department  - SLURM account/department name

This is step 2 of the UMR-seq SNP calling module: it filters each region's raw
calls to biallelic SNPs passing the missing data and minor allele frequency
thresholds. Re-run with different thresholds without repeating step 1.
Only run this once every step 1 array task has completed successfully."

#define step in the pipeline - should be the same name as the script
step=41-SNP_filter

######### Setup ################
regions_list=$1
input_dir=$2
output_dir=$3
max_missing=$4
min_maf=$5
walltime=$6
mem=$7
account_department=$8

if [ "$#" -lt "8" ]
then
echo "$usage"
exit -1
else
echo "Submitting regions listed in '$regions_list' for SNP filtering"
echo "Input directory: '$input_dir'"
echo "Output directory: '$output_dir'"
echo "Max missing: '$max_missing'"
echo "Min MAF: '$min_maf'"
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

#number of regions
# sbatch --array only takes a range; to handle 1 region, just use '1'
number_of_regions=`wc -l $regions_list | awk '{print $1}'`
if [[ "$number_of_regions" -eq 1 ]]
then
sbatch_t=1
else
sbatch_t="1-${number_of_regions}"
fi
echo "Number of regions: $number_of_regions"
echo "Argument to be passed to sbatch --array is '$sbatch_t'"

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

#submit sbatch and pass args
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the array list and the dir structures
sbatch --array $sbatch_t \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--export REGIONS_LIST=${regions_list},INPUT_DIR=${input_dir},OUTPUT_DIR=${output_dir},MAX_MISSING=${max_missing},MIN_MAF=${min_maf} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue --me"
echo "Check logs in: $log_folder"
