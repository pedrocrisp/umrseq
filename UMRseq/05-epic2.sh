#!/bin/bash -l
#SBATCH --job-name epic2
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
# conda env with epic2
# code developed using epic2 v0.0.41 - this versin does not support PE but PE option in newer version 0.0.52 gives weird results and 10x lower data coverage???
# use v 0.041 and NOT PE mode
# conda create --name epic2 python=3.8
# conda install -c bioconda epic2=0.0.41

conda activate $conda_enviro

########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {PBS_ARRAY_INDEX} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

#make adaligned folder bsmaped
cd analysis
mkdir -p ${bam_dir}_epic2

########## Run #################
# call peaks
# 50 bp bins gives good resolution on UMRs

epic2 \
--treatment $bam_dir/${ID}_sorted.bam \
--bin-size 50 \
--chromsizes $chrom_sizes_file \
--output ${bam_dir}_epic2/${ID}.50.epic2

echo finished summarising