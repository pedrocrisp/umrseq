#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 21b-UMR_consensus_merge_background_sbatch.sh <consensus_bed> <genome_file> <output_dir> <background_fraction> <seed> <walltime> <memory> <conda_enviro> <account_department>

Example:
bash 21b-UMR_consensus_merge_background_sbatch.sh ./umr_consensus/all_samples.umr.merged.consensus.noALT.bed genome.fa.fai ./umr_consensus 1.0 42 1:00:00 4 myenv my_department

Arguments:
  consensus_bed         - Step 2's consensus BED to use as the background length template, e.g.
                          '<out_prefix>.umr.merged.consensus.noALT.bed' (whole UMRs) or
                          '<out_prefix>.umr.merged.consensus.noALT.<bin_size>.bed' (binned UMRs,
                          if you want background regions matching the bin length instead). Output
                          files are named after this input file's basename (e.g.
                          '<out_prefix>.umr.merged.consensus.noALT.background.bed'), so runs against
                          different consensus_bed inputs never clash in the same output_dir
  genome_file           - Tab-delimited chromosome sizes file (chrom<TAB>size), for 'bedtools shuffle -g'.
                          A samtools '.fa.fai' index works directly since its first two columns match.
  output_dir            - Directory for background/merged output files (can be the same as step 2's output_dir)
  background_fraction   - Fraction of consensus UMRs to base the background set on, e.g. 1.0 for the same
                          number of background regions as UMRs, or 0.2 for 20%. The background regions are
                          a random subsample of the UMR set (so they inherit the UMR length distribution),
                          shuffled to new non-overlapping, non-UMR-overlapping genomic locations. A larger
                          fraction gives a smoother, more robust low-coverage KDE peak in steps 9-11's
                          within-sample calling at the cost of more loci to measure coverage over; 1.0 is a
                          reasonable default. Must be > 0 and <= 1.0
  seed                  - Integer random seed, for reproducible subsampling/shuffling
  walltime              - Job walltime (HH:MM:SS format)
  memory                - Memory in GB for the job
  conda_enviro          - Name of the conda environment to activate (must provide bedtools, or load it via
                          'module load' in 21b-UMR_consensus_merge_background.sh)
  account_department    - SLURM account/department name

This is an optional add-on to step 2 (21-UMR_consensus_merge_sbatch.sh): it
samples a set of random, non-UMR background regions matching the consensus
UMR length distribution, and writes both a standalone background BED/SAF and
a combined UMR+background BED/SAF. Use the combined BED in place of step 2's
plain consensus BED as the 'consensus_bed' input to step 9
(33-UMR_coverage_sbatch.sh) - the background regions give the within-sample
calling algorithm (steps 9-11) a genuine low-coverage 'noise' population to
contrast against, helping samples that would otherwise look unimodal split
into a clear bimodal present/absent distribution. Only run this once step 2
has completed. Background region IDs are prefixed 'BG_' (vs UMRs'
'CON_UMR_'/'ALT_CON_UMR_'), so they can be filtered out of downstream tables
if you only want true UMR calls."

#define step in the pipeline - should be the same name as the script
step=21b-UMR_consensus_merge_background

######### Setup ################
consensus_bed=$1
genome_file=$2
output_dir=$3
background_fraction=$4
seed=$5
walltime=$6
mem=$7
conda_enviro=$8
account_department=$9

if [ "$#" -lt "9" ]
then
echo "$usage"
exit -1
else
echo "Building background regions from '$consensus_bed'"
echo "Genome file: '$genome_file'"
echo "Output directory: '$output_dir'"
echo "Background fraction: '$background_fraction'"
echo "Seed: '$seed'"
fi

#check that the consensus BED and genome file exist
if [ ! -f "$consensus_bed" ]; then
    echo "ERROR: Consensus BED not found (did step 2 finish?): $consensus_bed"
    exit -1
fi
if [ ! -f "$genome_file" ]; then
    echo "ERROR: Genome file not found: $genome_file"
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
cp "$consensus_bed" ${log_folder}/consensus.bed
cp "$genome_file" ${log_folder}/genome_file

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
--export CONSENSUS_BED=${consensus_bed},GENOME_FILE=${genome_file},OUTPUT_DIR=${output_dir},BACKGROUND_FRACTION=${background_fraction},SEED=${seed},conda_enviro=${conda_enviro} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Job submitted! Monitor with: squeue -u \$USER"
echo "Check logs in: $log_folder"
