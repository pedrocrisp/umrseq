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

###### Set up digestion operatives from motifs-regex.txt#####
### e.g. CNNR	[Cc][ACGTacgt][ACGTacgt][AGag]	+"""
LINE="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"
PATTERN=$(echo "$LINE" | cut -d $'\t' -f 1)
echo "$PATTERN"
REGEX=$(echo "$LINE" | cut -d $'\t' -f 2)
echo "$REGEX"
STRAND=$(echo "$LINE" | cut -d $'\t' -f 3)
echo "$STRAND"

echo sample is being digested by $PATTERN

{ seqhax grepbed -p $REGEX $genome || \
${gitdir}/seqhax/build/bin/seqhax grepbed -p $REGEX $genome; } \
> ${output}-tmp/$PATTERN-recognition-sites.txt

sed -i "s/$/\t"$PATTERN"\t"$STRAND"/" ${output}-tmp/$PATTERN-recognition-sites.txt

python3 ${scriptdir}/find_cut_sites.py \
${output}-tmp/$PATTERN-recognition-sites.txt \
$genome_size > ${output}-tmp/${PATTERN}-cuts.txt

conda deactivate
