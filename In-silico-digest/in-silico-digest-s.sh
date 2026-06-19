#!/bin/bash
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

###### Modules ################
# Requires seqhax
module load gcc/12.3.0 miniconda3/23.9.0-0
source $EBROOTMINICONDA3/etc/profile.d/conda.sh
conda activate $env

###### Set up directories #####
LINE="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"
PATTERN=$(echo $LINE | cut -d " " -f 1)
REGEX=$(echo $LINE | cut -d " " -f 2)
STRAND=$(echo $LINE | cut -d " " -f 3)

echo sample is being digested by $PATTERN

cd analysis

seqhax grepbed -p $REGEX $genome || \
${gitdir}/seqhax/build/bin/seqhax grepbed -p $REGEX $genome \
> ${output}-tmp/$PATTERN-digest.txt

sed -i "s/$/\t"$PATTERN"\t"$STRAND"/" ${output}-tmp/${PATTERN}-digest.txt

python3 ${scriptdir}/find_cut_sites.py \
$output-tmp/${PATTERN}-digest.txt \
$genome_size > ${output}-tmp/${PATTERN}-cuts.txt

conda deactivate
