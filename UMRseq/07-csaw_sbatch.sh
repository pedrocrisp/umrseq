#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 07-csaw_sbatch.sh <contrasts_list.txt> <walltime> <memory> <DMR_contrasts_table_file>
<path_to_data_files> <blacklist> <filter_FC> <bin_size> <window_spacing>
<account_department>
"

# <genome_annotation> <chromosome_sizes> <TE_annotation>

#define step in the pipeline - should be the same name as the script
step=07-csaw

######### Setup ################
sample_list=$1
walltime=$2
mem=$3
DMR_contrasts_table_file=$4
path_to_data_files=$5
blacklist=$6
filter_FC=$7
bin_size=$8
window_spacing=$9
# genome_annotation=${10}
# chromosome_sizes=${11}
# TE_annotation=${12}
account_department=${10}


if [ "$#" -lt "10" ]
then
echo $usage
exit -1
else
echo "CSAW '$sample_list' "
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
--cpus-per-task 2 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--export LIST=${sample_list},DMR_contrasts_table_file=$DMR_contrasts_table_file,path_to_data_files=$path_to_data_files,blacklist=$blacklist,filter_FC=$filter_FC,bin_size=$bin_size,window_spacing=$window_spacing \
--account $account_department \
$script_to_sbatch

