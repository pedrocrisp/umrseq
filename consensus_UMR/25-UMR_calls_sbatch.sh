#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 25-UMR_calls_sbatch.sh <batch_list.txt> <output_dir> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 25-UMR_calls_sbatch.sh ./umr_calling/batches/batch_list.txt ./umr_calling/calls 2:00:00 30 myenv my_department

Arguments:
  batch_list.txt      - List of batch file paths (one per line), produced by 24-UMR_combine_calls_sbatch.sh
                         at '<output_dir>/batches/batch_list.txt'
  output_dir          - Directory for per-batch '<batch_id>.calls' and '<batch_id>.UMR.stats.txt' files
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB per job
  conda_enviro        - Name of the conda environment to activate (must provide numpy, statsmodels, findpeaks)
  account_department  - SLURM account/department name

This is step 2 of the UMR calling pipeline: it calls each UMR present/absent
per sample, using the count distribution modelled in 25-UMR_calls.py. One
array task per batch. Only run this once step 1 (24-UMR_combine_calls_sbatch.sh)
has completed."

#define step in the pipeline - should be the same name as the script
step=25-UMR_calls

######### Setup ################
batch_list=$1
output_dir=$2
walltime=$3
mem=$4
conda_enviro=$5
account_department=$6

if [ "$#" -lt "6" ]
then
echo "$usage"
exit -1
else
echo "Submitting batches listed in '$batch_list' for UMR calling"
echo "Output directory: '$output_dir'"
fi

#check that the batch list exists
if [ ! -f "$batch_list" ]; then
    echo "ERROR: Batch list not found: $batch_list"
    exit -1
fi

#number of batches
# sbatch -J only takes a range; to handle 1 batch, just use '1'
number_of_batches=`wc -l $batch_list | awk '{print $1}'`
if [[ "$number_of_batches" -eq 1 ]]
then
sbatch_t=1
else
sbatch_t="1-${number_of_batches}"
fi
echo "Number of batches: $number_of_batches"
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
cp $batch_list ${log_folder}/batch_list.txt

#submit sbatch and pass args
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the array list and the dir structures
sbatch --array $sbatch_t \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 2 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--export LIST=${batch_list},OUTPUT_DIR=${output_dir},SCRIPT_DIR=${scriptdir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
