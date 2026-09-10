#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 34-UMR_within_sample_calls_sbatch.sh <sample_list.txt> <coverage_dir> <output_dir> <shift> <bw> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 34-UMR_within_sample_calls_sbatch.sh samples.txt ./umr_coverage ./umr_within_sample_calls 0.2 sj 1:00:00 4 myenv my_department

Arguments:
  sample_list.txt     - Same sample list used in step 1 (33-UMR_coverage)
  coverage_dir        - Directory containing '<sample_prefix>.regions.bed.gz' files (step 1's output_dir)
  output_dir          - Directory for per-sample calls/stats files and plots/ subdirectory
  shift               - Fraction of the distance from the 2nd valley to the neighbouring peak to shift the
                         present/absent cutoff towards (e.g. 0.2 - see 34-UMR_within_sample_calls.py)
  bw                  - KDE bandwidth selector, 'sj' (Sheather-Jones plug-in via KDEpy - recommended, adapts
                         to bimodal/multimodal coverage distributions) or 'normal_reference' (statsmodels'
                         rule-of-thumb default, which tends to oversmooth multimodal data)
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB per job
  conda_enviro        - Name of the conda environment to activate (must provide numpy, statsmodels, findpeaks,
                         KDEpy, matplotlib)
  account_department  - SLURM account/department name

This is step 2 of the within-sample UMR calling workflow: for each sample, it
fits a KDE to that sample's UMR coverage values, looks for a bimodal split,
and calls every UMR present/absent against the shifted valley cutoff. One
array task per sample. Samples without a bimodal coverage distribution are
skipped (a warning, not a job failure) - see 'Calling algorithm' in
README_UMR_CONSENSUS.md. Only run this once step 1
(33-UMR_coverage_sbatch.sh) has completed."

#define step in the pipeline - should be the same name as the script
step=34-UMR_within_sample_calls

######### Setup ################
sample_list=$1
coverage_dir=$2
output_dir=$3
shift_frac=$4
bw=$5
walltime=$6
mem=$7
conda_enviro=$8
account_department=$9

if [ "$#" -lt "9" ]
then
echo "$usage"
exit -1
else
echo "Submitting samples listed in '$sample_list' for within-sample UMR calling"
echo "Coverage directory: '$coverage_dir'"
echo "Output directory: '$output_dir'"
echo "Cutoff shift: '$shift_frac'"
echo "KDE bandwidth selector: '$bw'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that coverage directory exists
if [ ! -d "$coverage_dir" ]; then
    echo "ERROR: Coverage directory not found: $coverage_dir"
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
cp $sample_list ${log_folder}/sample_list.txt

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
--export LIST=${sample_list},COVERAGE_DIR=${coverage_dir},OUTPUT_DIR=${output_dir},SHIFT=${shift_frac},BW=${bw},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
