#!/bin/bash -l
#SBATCH --job-name macs2
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
# module load macs2
conda activate $conda_enviro
# conda create --name macs2 python=3.7
# conda activate macs2
# conda install -c bioconda macs2

###### Set up directories #####
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

cd analysis
mkdir -p macs2

##### Errors ##################
if ([ $paired_end == "yes" ] || [ $paired_end == "no" ])
then
echo "Is paried end = " $paired_end
else
echo "Library type not specified correctly."
echo "Please indicate:"
echo "yes for PE"
echo "no for SE"
exit 1111
fi

if [ "$filter" == "yes" ]
then
input="-t ${reads_folder}_filtered/${ID}_sorted_NoDup_ProPairs.bam"
control_input="-c ${reads_folder}_filtered/${control}_sorted_NoDup_ProPairs.bam"
fi

if [ "$filter" == "no" ]
then
input="-t ${reads_folder}/${ID}_sorted.bam"
control_input="-c ${reads_folder}/${control}_sorted.bam"
fi

macs2_cmd="macs2 callpeak \
$input \
-g $genome_size \
-n ${ID}_test \
--outdir macs2"


if [ "$paired_end" == "yes" ]
then
macs2_cmd="$macs2_cmd -f BAMPE"
fi

if [ "$paired_end" == "no" ]
then
macs2_cmd="$macs2_cmd -f BAM"
fi

if [ "$broad" == "yes" ]
then
macs2_cmd="$macs2_cmd --broad"
fi

if [ -n "$control" ]
then
macs2_cmd="$macs2_cmd $control_input"
fi

$macs2_cmd

echo "MACS2 finished running"
exit 0
