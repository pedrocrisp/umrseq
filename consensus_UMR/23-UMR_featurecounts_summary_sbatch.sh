#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 23-UMR_featurecounts_summary_sbatch.sh <sample_list.txt> <counts_dir> <output_dir> <out_prefix> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 23-UMR_featurecounts_summary_sbatch.sh samples.txt ./umr_counts ./umr_counts all_samples 0:30:00 2 myenv my_department

Arguments:
  sample_list.txt     - File containing sample name prefixes (one per line) - same prefixes used in step 3 (22-UMR_featurecounts)
  counts_dir          - Directory containing '<sample_prefix>.featurecounts.counts.summary' files (step 3's output_dir)
  output_dir          - Directory for the summary table
  out_prefix          - Prefix used to name the output table (e.g. all_samples)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate
  account_department  - SLURM account/department name

This is step 4 of the UMR consensus pipeline. Only run this once step 3's
array job (22-UMR_featurecounts_sbatch.sh) has completed successfully for
every sample in sample_list.txt - this step is a single job (not an array)
that reads every sample's featureCounts summary file and reports, per
sample, the total reads, reads assigned to a consensus UMR, and percent
assigned."

#define step in the pipeline - should be the same name as the script
step=23-UMR_featurecounts_summary

######### Setup ################
sample_list=$1
counts_dir=$2
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
echo "Building read support summary for samples listed in '$sample_list'"
echo "Counts directory: '$counts_dir'"
echo "Output directory: '$output_dir'"
echo "Output prefix: '$out_prefix'"
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
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export LIST=${sample_list},COUNTS_DIR=${counts_dir},OUTPUT_DIR=${output_dir},OUT_PREFIX=${out_prefix},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
