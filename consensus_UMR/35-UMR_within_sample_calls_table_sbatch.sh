#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 35-UMR_within_sample_calls_table_sbatch.sh <sample_list.txt> <calls_dir> <output_dir> <out_prefix> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 35-UMR_within_sample_calls_table_sbatch.sh samples.txt ./umr_within_sample_calls ./umr_within_sample_calls all_samples 0:30:00 2 myenv my_department

Arguments:
  sample_list.txt     - Same sample list used in steps 1-2 (defines the output table's column order)
  calls_dir           - Directory containing '<sample_prefix>.coverage.calls.tsv' files (step 2's output_dir)
  output_dir          - Directory for the final call table
  out_prefix          - Prefix used to name the output table (e.g. all_samples)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate (needs only Python 3 standard library)
  account_department  - SLURM account/department name

This is step 3 of the within-sample UMR calling workflow (single job, not
array): it joins every sample's '<sample_prefix>.coverage.calls.tsv' into one
'<out_prefix>.UMR.within_sample.calls.tsv' table (UMR_ID rows, sample
columns, YES/NO recoded as 1/0). Samples with no calls file (a non-bimodal
coverage distribution in step 2) are filled with NA rather than treated as
an error. Only run this once step 2's array job
(34-UMR_within_sample_calls_sbatch.sh) has completed for every sample."

#define step in the pipeline - should be the same name as the script
step=35-UMR_within_sample_calls_table

######### Setup ################
sample_list=$1
calls_dir=$2
output_dir=$3
out_prefix=$4
walltime=$5
mem=$6
conda_enviro=$7
account_department=$8

if [ "$#" -lt "8" ]
then
echo "$usage"
exit -1
else
echo "Building within-sample UMR calls table for samples listed in '$sample_list'"
echo "Calls directory: '$calls_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that the sample list and calls directory exist
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
--export SAMPLE_LIST=${sample_list},CALLS_DIR=${calls_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix},SCRIPT_DIR=${scriptdir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
