#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 26-UMR_calls_table_sbatch.sh <batch_list.txt> <sample_list.txt> <calls_dir> <output_dir> <out_prefix> <walltime> <memory> <account_department>

Example:
bash 26-UMR_calls_table_sbatch.sh ./umr_calling/batches/batch_list.txt samples.txt ./umr_calling/calls ./umr_calling all_samples 0:30:00 4 my_department

Arguments:
  batch_list.txt      - Same batch list used for step 2 (24-UMR_combine_calls's '<output_dir>/batches/batch_list.txt')
  sample_list.txt     - Same sample list used in steps 1-3 (defines the column order in the output table)
  calls_dir           - Directory containing '<batch_id>.calls' files (step 2's output_dir)
  output_dir          - Directory for the final call table
  out_prefix          - Prefix used to name the output table (e.g. all_samples)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  account_department  - SLURM account/department name

This is step 3 of the UMR calling pipeline (single job, not array): it
concatenates every batch's '.calls' file, recodes YES/NO as 1/0, and writes
one '<out_prefix>.UMR.calls.tsv' table. Only run this once step 2's array job
(25-UMR_calls_sbatch.sh) has completed successfully for every batch."

#define step in the pipeline - should be the same name as the script
step=26-UMR_calls_table

######### Setup ################
batch_list=$1
sample_list=$2
calls_dir=$3
output_dir=$4
out_prefix=$5
walltime=$6
mem=$7
account_department=$8

if [ "$#" -lt "8" ]
then
echo "$usage"
exit -1
else
echo "Building UMR calls table"
echo "Batch list: '$batch_list'"
echo "Sample list: '$sample_list'"
echo "Calls directory: '$calls_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
fi

#check that the batch list, sample list, and calls directory exist
if [ ! -f "$batch_list" ]; then
    echo "ERROR: Batch list not found: $batch_list"
    exit -1
fi
if [ ! -f "$sample_list" ]; then
    echo "ERROR: Sample list not found: $sample_list"
    exit -1
fi
if [ ! -d "$calls_dir" ]; then
    echo "ERROR: Calls directory not found: $calls_dir"
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
cp $batch_list ${log_folder}/batch_list.txt
cp $sample_list ${log_folder}/sample_list.txt

#submit sbatch (single job, no array - this step needs every batch's output at once)
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the lists and dir structures
sbatch \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export BATCH_LIST=${batch_list},SAMPLE_LIST=${sample_list},CALLS_DIR=${calls_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
