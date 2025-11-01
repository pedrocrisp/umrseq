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
module load macs2/2.2.9.1
# current module is 
# conda activate $conda_enviro
# conda create --name macs2 python=3.7
# conda activate macs2
# conda install -c bioconda macs2
# macs2 2.2.6

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
fi

if [ "$filter" == "no" ]
then
input="-t ${reads_folder}/${ID}*sorted.bam"
fi

# control is optional
# currently, script wont work if deduplication was undertaken and a control is used too
if [ "$control" == "no" ]
then
control_input=""
echo "User specified to not use a control sample"
else
control_input="-c ${reads_folder}/${control}*sorted.bam"
fi



# 1/11/25 Pete added additional options
# -B --SPMR output CPM normalised bedfiles
# --nomodel Disables MACS2's fragment size modeling
# UMR-seq has diverse fragment sizes, we don't want MACS2 to model a single fragment size
# --keep-dup all
# --bdg --SPMR \

macs2_cmd="macs2 callpeak \
$input \
-g $genome_size \
-n ${ID} \
--nomodel \
--keep-dup all \
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

if [ -n "$control_input" ]
then
macs2_cmd="$macs2_cmd $control_input"
fi

$macs2_cmd

echo "MACS2 finished running"
exit 0
