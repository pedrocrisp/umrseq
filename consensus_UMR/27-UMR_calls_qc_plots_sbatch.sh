#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 27-UMR_calls_qc_plots_sbatch.sh <calls_table> <cpm_matrix> <output_dir> <n_umrs> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 27-UMR_calls_qc_plots_sbatch.sh ./umr_calling/all_samples.UMR.calls.tsv ./umr_calling/all_samples.umr_counts.cpm.tsv ./umr_calling/qc_plots 1000 2:00:00 8 myenv my_department

Arguments:
  calls_table         - Step 3's '<out_prefix>.UMR.calls.tsv' (source of called UMR IDs to sample from)
  cpm_matrix          - Step 1's '<out_prefix>.umr_counts.cpm.tsv' (full, unbatched CPM matrix)
  output_dir          - Directory for the QC sample files and plots/ subdirectory
  n_umrs              - Number of random called UMRs to plot
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB for the job
  conda_enviro        - Name of the conda environment to activate (must provide numpy, statsmodels, findpeaks, matplotlib)
  account_department  - SLURM account/department name

Optional diagnostic step: generates a KDE plot and a peak/valley plot (with
the chosen present/absent cutoff marked) for a random sample of UMRs that
were called in step 3, so you can visually spot-check the cutoffs. Not part
of the core calls table - run any time after step 3 (26-UMR_calls_table_sbatch.sh)."

#define step in the pipeline - should be the same name as the script
step=27-UMR_calls_qc_plots

######### Setup ################
calls_table=$1
cpm_matrix=$2
output_dir=$3
n_umrs=$4
walltime=$5
mem=$6
conda_enviro=$7
account_department=$8

if [ "$#" -lt "8" ]
then
echo "$usage"
exit -1
else
echo "Building UMR calling QC plots"
echo "Calls table: '$calls_table'"
echo "CPM matrix: '$cpm_matrix'"
echo "Output directory: '$output_dir'"
echo "Number of UMRs to sample: '$n_umrs'"
fi

#check that the calls table and cpm matrix exist
if [ ! -f "$calls_table" ]; then
    echo "ERROR: Calls table not found: $calls_table"
    exit -1
fi
if [ ! -f "$cpm_matrix" ]; then
    echo "ERROR: CPM matrix not found: $cpm_matrix"
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

#submit sbatch (single job, no array)
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the input files and dir structures
sbatch \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%j \
-e ${log_folder}/${step}_e_%j \
--export CALLS_TABLE=${calls_table},CPM_MATRIX=${cpm_matrix},OUTPUT_DIR=${output_dir},N_UMRS=${n_umrs},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
