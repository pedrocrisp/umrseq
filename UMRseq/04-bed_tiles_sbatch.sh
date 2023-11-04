#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 03-bed_bigWig_tiles_sbatch.sh <sample_list.txt> <chrom.sizes file> <reference_tile_file> <bam_dir> <CPM_filter> <walltime> <memory> <account_department>
"

# NOTE: NOT USING THIS SCRIPT ANY MORE - USING 03b - DEEPTOOLS TO DO THE BINNING

#define stepo in the pipeline - should be the same name as the script
step=04-bed_tiles

######### Setup ################
sample_list=$1
chrom_sizes=$2
reference_tile_file=$3
bam_dir=$4
CPM_filter_UMRs=$5
walltime=$6
mem=$7
account_department=$8

if [ "$#" -lt "7" ]
then
echo $usage
exit -1
else
echo "Submitting samples listed in '$sample_list' for binning"
cat $sample_list
fi

#number of samples
number_of_samples=`wc -l $sample_list | awk '{print $1}'`
if [[ "$number_of_samples" -eq 1 ]]
then
sbatch_t=1
else
sbatch_t="1-${number_of_samples}"
fi
echo "argument to be passed to sbatch -t is '$sbatch_t'"

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

#make analysis dir if it doesnt exist yet
analysis_dir=analysis
mkdir -p $analysis_dir

#make trimmgalore logs folder, timestamped
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

#script path and cat a record of what was run
script_to_sbatch=${scriptdir}/${step}.sh
cat $script_to_sbatch > ${log_folder}/script.log
cat $0 > ${log_folder}/sbatch_runner.log

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
--export LIST=${sample_list},chrom_sizes=${chrom_sizes},reference_tile_file=${reference_tile_file},bam_dir=${bam_dir},CPM_filter_UMRs=${CPM_filter_UMRs} \
--account $account_department \
$script_to_sbatch
