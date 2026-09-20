#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 21-UMR_consensus_merge_sbatch.sh <sample_list.txt> <file_suffix> <names_dir> <output_dir> <out_prefix> <bin_size> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 21-UMR_consensus_merge_sbatch.sh samples.txt .UMR.epic2.bed ./umr_names ./umr_consensus all_samples 50 4:00:00 8 myenv my_department

Arguments:
  sample_list.txt     - File containing sample name prefixes (one per line) - same file used for step 1
  file_suffix         - Suffix used for input UMR BED files in step 1 (e.g., .UMR.epic2.bed)
  names_dir           - Directory containing the '<sample><suffix>.names' files produced by step 1
                         (this is step 1's output_dir)
  output_dir          - Directory for cohort consensus output files
  out_prefix          - Prefix used to name cohort output files (e.g., all_samples)
  bin_size            - Size in bp of the consecutive sub-bins each consensus UMR is split into
                         (e.g. 50). Leftover bp when a UMR's length isn't an exact multiple of
                         bin_size are trimmed evenly from both ends before binning. UMRs shorter
                         than bin_size produce no bins. Each bin is named '<parent_id>.<n>'
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate (must provide bedtools,
                         or load it via 'module load' in 21-UMR_consensus_merge.sh)
  account_department  - SLURM account/department name

This is step 2 in the UMR consensus pipeline. Only run this once step 1's
array job (20-EPIC2_reformat_sbatch.sh) has completed successfully for every
sample in sample_list.txt - this step is a single job (not an array) that
merges all samples into a cohort consensus."

#define step in the pipeline - should be the same name as the script
step=21-UMR_consensus_merge

######### Setup ################
sample_list=$1
file_suffix=$2
names_dir=$3
output_dir=$4
out_prefix=$5
bin_size=$6
walltime=$7
mem=$8
conda_enviro=$9
account_department=${10}

if [ "$#" -lt "10" ]
then
echo "$usage"
exit -1
else
echo "Building UMR cohort consensus for samples listed in '$sample_list'"
echo "File suffix: '$file_suffix'"
echo "Names directory: '$names_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
echo "Bin size: '$bin_size'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that names directory exists
if [ ! -d "$names_dir" ]; then
    echo "ERROR: Names directory not found: $names_dir"
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

#make log and analysis folders
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
cp $sample_list ${log_folder}/sample_list.txt

#submit sbatch (single job, no array - this step needs every sample's output at once)
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the sample list and dir structures
sbatch \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export LIST=${sample_list},SUFFIX=${file_suffix},NAMES_DIR=${names_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix},BIN_SIZE=${bin_size},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue --me"
echo "Check logs in: $log_folder"
