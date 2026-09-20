#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 33-UMR_coverage_sbatch.sh <sample_list.txt> <file_suffix> <consensus_bed> <input_dir> <output_dir> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 33-UMR_coverage_sbatch.sh samples.txt .pe.rd.bam ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed ./bams ./umr_coverage 4:00:00 8 myenv my_department

Arguments:
  sample_list.txt     - File containing sample name prefixes (one per line)
  file_suffix         - Suffix of each sample's BAM file (e.g., .pe.rd.bam). Matched as '<sample_prefix>*<file_suffix>'
                         so any text between the prefix and suffix (e.g. a cultivar name) doesn't need to be listed
  consensus_bed       - Consensus UMR intervals (BED3+), produced by 21-UMR_consensus_merge.sh
                         (<out_prefix>.umr.merged.consensus.noALT.bed) - the same consensus used by the
                         featureCounts-based workflow (step 22), reused here so both workflows call
                         presence/absence on identical UMR intervals
  input_dir           - Directory containing per-sample BAM files (BAM + index required)
  output_dir          - Directory for per-sample mosdepth output
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB per job
  conda_enviro        - Name of the conda environment to activate (must provide mosdepth)
  account_department  - SLURM account/department name

This is step 1 of the within-sample UMR calling workflow (an alternative to
steps 22-27, suited to a small number of samples rather than a large cohort -
see README_UMR_CONSENSUS.md): it computes, per sample, the mean read depth
over each consensus UMR interval using mosdepth. One array task per sample."

#define step in the pipeline - should be the same name as the script
step=33-UMR_coverage

######### Setup ################
sample_list=$1
file_suffix=$2
consensus_bed=$3
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
echo "Submitting samples listed in '$sample_list' for UMR coverage calculation"
echo "File suffix: '$file_suffix'"
echo "Consensus BED: '$consensus_bed'"
echo "Input directory: '$input_dir'"
echo "Output directory: '$output_dir'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check that the consensus BED exists
if [ ! -f "$consensus_bed" ]; then
    echo "ERROR: Consensus BED file not found: $consensus_bed"
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
cp $sample_list ${log_folder}/sample_list.txt
cp $consensus_bed ${log_folder}/consensus.bed

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
--export LIST=${sample_list},SUFFIX=${file_suffix},CONSENSUS_BED=${consensus_bed},INPUT_DIR=${input_dir},OUTPUT_DIR=${output_dir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
