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
mkdir -p ${bam_dir}_epic2_${bin_Size}

########## Run #################
# call peaks
# 50 bp bins gives good resolution on UMRs

# this implementation does not use a background library
# can also be run in df mode to compare samples

epic2 \
--treatment $bam_dir/${ID}_sorted.bam \
--bin-size $bin_Size \
--chromsizes $chrom_sizes_file \
--output ${bam_dir}_epic2/${ID}.50.epic2

# remove header to make bed file
grep -v "^#" ${bam_dir}_epic2/${ID}.50.epic2 > ${bam_dir}_epic2/${ID}.50.epic2.bed

# remove file with header
rm ${bam_dir}_epic2/${ID}.50.epic2

# outout
# ChIPCount is the coverage metric
# score is somethign internal to scicer and doesent mean much unless run with an input background library
# https://github.com/biocore-ntnu/epic2

# #Chromosome     Start   End     ChIPCount       Score   Strand
# 1       15600   16099   25      30.58030867576599       .
# 1       16950   17449   116     1188.359456539154       .
# 1       22000   25449   277     474.23892998695374      .
# 1       43600   44849   99      146.5398440361023       .

echo finished summarising