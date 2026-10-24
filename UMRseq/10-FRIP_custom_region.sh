#!/bin/bash -l
#SBATCH --job-name FRIP-custom
#SBATCH --requeue
#SBATCH --partition=general

########## QC #################
set -xeuo pipefail

echo ------------------------------------------------------
echo SBATCH: working directory is $SLURM_SUBMIT_DIR
echo SBATCH: job identifier is $SLURM_JOBID
echo SBATCH: array_ID is ${SLURM_ARRAY_TASK_ID}
echo ------------------------------------------------------

echo working dir is $PWD

#cd into work dir
echo changing to SLURM_SUBMIT_DIR
cd "$SLURM_SUBMIT_DIR"
echo working dir is now $PWD

########## Modules #################
# dependencies
# conda env with deeptools
# see 03 or 06 for example installs
module load miniconda3/23.9.0-0
source $EBROOTMINICONDA3/etc/profile.d/conda.sh

conda activate $conda_enviro

########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {PBS_ARRAY_INDEX} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

#make adaligned folder bsmaped
cd analysis
mkdir -p ${bam_dir}_FRIP_${region_name}

####### FRIP module #######
# calculate FRIP using deeptools
# this module calculates the fraction of reads in the region file provided
# for example, provide a WGBS UMR file to calculat the percent of reads in WGBS UMRs

plotEnrichment \
-b $bam_dir/${ID}_sorted.bam \
--BED ${region_file} \
--blackListFileName $blacklist \
-p 2 \
-o ${bam_dir}_FRIP_${region_name}/${ID}_FRIP.pdf \
--outRawCounts ${bam_dir}_FRIP_${region_name}/${ID}_FRIP_counts.tab

echo finished summarising