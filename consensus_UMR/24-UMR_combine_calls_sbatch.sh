#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 24-UMR_combine_calls_sbatch.sh <sample_list.txt> <counts_dir> <output_dir> <out_prefix> <batch_size> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 24-UMR_combine_calls_sbatch.sh samples.txt ./umr_counts ./umr_calling all_samples 1000 3:00:00 20 myenv my_department

Arguments:
  sample_list.txt     - File containing sample name prefixes (one per line) - same prefixes used in step 3 (22-UMR_featurecounts)
  counts_dir          - Directory containing '<sample_prefix>.featurecounts.counts' files (step 3's output_dir)
  output_dir          - Directory for the combined matrix, CPM tables, and batch files
  out_prefix          - Prefix used to name the combined output tables (e.g. all_samples)
  batch_size          - Target number of UMRs per batch (the module computes how many batches that implies)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate (must provide R with edgeR + tibble)
  account_department  - SLURM account/department name

This is step 1 of the UMR calling pipeline (single job, not array): it builds
a UMR x sample read count matrix from step 3's featureCounts output,
CPM-normalises it, and splits it into batches of UMRs for parallel
presence/absence calling in step 2 (25-UMR_calls_sbatch.sh)."

#define step in the pipeline - should be the same name as the script
step=24-UMR_combine_calls

######### Setup ################
sample_list=$1
counts_dir=$2
output_dir=$3
out_prefix=$4
batch_size=$5
walltime=$6
mem=$7
conda_enviro=$8
account_department=$9

if [ "$#" -lt "9" ]
then
echo "$usage"
exit -1
else
echo "Combining UMR counts for samples listed in '$sample_list'"
echo "Counts directory: '$counts_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
echo "Target batch size: '$batch_size' UMRs/batch"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that counts directory exists
if [ ! -d "$counts_dir" ]; then
    echo "ERROR: Counts directory not found: $counts_dir"
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
--cpus-per-task 2 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export LIST=${sample_list},COUNTS_DIR=${counts_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix},BATCH_SIZE=${batch_size},SCRIPT_DIR=${scriptdir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
echo ""
echo "Once this job completes, run step 2:"
echo "  bash 25-UMR_calls_sbatch.sh ${output_dir}/batches/batch_list.txt <calls_output_dir> <walltime> <memory> $conda_enviro $account_department"
