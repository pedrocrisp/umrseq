#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash recombine_bed_sbatch.sh <sample_list.txt> <file_suffix> <conversion_table.csv> <input_dir> <output_dir> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash recombine_bed_sbatch.sh samples.txt .bed conversion_table.csv ./beds ./beds_combined 4:00:00 4 myenv my_department

Arguments:
  sample_list.txt       - File containing sample name prefixes (one per line)
  file_suffix          - Suffix for input files (e.g., .bed or _peaks.bed)
  conversion_table.csv - CSV file with chromosome conversion information
  input_dir            - Directory containing input BED files
  output_dir           - Directory for output BED files
  walltime             - Job walltime (HH:MM:SS format)
  memory               - Memory in GB per job
  conda_enviro         - Name of the conda environment to activate
  account_department   - SLURM account/department name"

#define step in the pipeline - should be the same name as the script
step=recombine_bed

######### Setup ################
sample_list=$1
file_suffix=$2
conversion_table=$3
input_dir=$4
output_dir=$5
walltime=$6
mem=$7
conda_enviro=$8
account_department=$9

if [ "$#" -lt "9" ]
then
echo "$usage"
exit -1
else
echo "Submitting samples listed in '$sample_list' for chromosome recombination"
echo "File suffix: '$file_suffix'"
echo "Conversion table: '$conversion_table'"
echo "Input directory: '$input_dir'"
echo "Output directory: '$output_dir'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that conversion table exists
if [ ! -f "$conversion_table" ]; then
    echo "ERROR: Conversion table not found: $conversion_table"
    exit -1
fi

#check that input directory exists
if [ ! -d "$input_dir" ]; then
    echo "ERROR: Input directory not found: $input_dir"
    exit -1
fi

#number of samples
# sbatch -J only takes a range; to handle 1 sample, just use '1'
number_of_samples=`wc -l $sample_list | awk '{print $1}'`
if [[ "$number_of_samples" -eq 1 ]]
then
sbatch_t=1
else
sbatch_t="1-${number_of_samples}"
fi
echo "Number of samples: $number_of_samples"
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
cp $conversion_table ${log_folder}/conversion_table.csv

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
--export LIST=${sample_list},SUFFIX=${file_suffix},CONVERSION_TABLE=${conversion_table},INPUT_DIR=${input_dir},OUTPUT_DIR=${output_dir},SCRIPT_DIR=${scriptdir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
