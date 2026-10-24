#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 43-UMR_calls_to_vcf_sbatch.sh <calls_table.tsv> <output_dir> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 43-UMR_calls_to_vcf_sbatch.sh ./umr_calling/all_samples.UMR.calls.tsv ./umr_calling 0:30:00 4 myenv my_department

Arguments:
  calls_table.tsv     - UMR x sample call table: step 7's '<out_prefix>.UMR.calls.tsv' or step 11's
                         '<out_prefix>.UMR.within_sample.calls.tsv'. The output VCF is named after this
                         file's basename with '.tsv' replaced by '.vcf'
  output_dir          - Directory for the output VCF
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate (must provide python3)
  account_department  - SLURM account/department name

Optional step: converts UMR presence/absence calls (1/0/NA) into a placeholder
VCF (UMRs as sites on a dummy chromosome 'chrU', 1 -> 1/1, 0 -> 0/0, NA -> ./.)
so they can be analysed with the same tools as SNPs. Single job. Run any time
after step 7 or step 11."

#define step in the pipeline - should be the same name as the script
step=43-UMR_calls_to_vcf

######### Setup ################
calls_table=$1
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
echo "Converting UMR calls table '$calls_table' to VCF"
echo "Output directory: '$output_dir'"
fi

#check that the calls table exists
if [ ! -f "$calls_table" ]; then
    echo "ERROR: Calls table not found: $calls_table"
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

#make log folders
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

#submit sbatch (single job, no array)
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the dir structures
sbatch \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export CALLS_TABLE=${calls_table},OUTPUT_DIR=${output_dir},SCRIPT_DIR=${scriptdir},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue --me"
echo "Check logs in: $log_folder"
