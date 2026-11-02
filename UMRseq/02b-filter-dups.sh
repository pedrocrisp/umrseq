#!/bin/bash
#SBATCH --job-name filter-dups
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

########## Variables ###############

export RUN_PICARD="java -jar $PICARD_PATH"

########## Modules #################
module load java/21.0.8
module load bamtools/2.5.3-gcc-14.2.0
# module load bamtools/2.5.2-gcc-12.3.0
# module load bamtools/2.5.2-gcc-10.3.0

# *** updating samtools to gcc-11.3 (but v11 also being phased out in 2026 - test samtools/1.18-gcc-12.3.0)
# module load samtools/1.13-gcc-10.3.0 ***
module load samtools/1.13-gcc-11.3.0
# samtools/1.18-gcc-12.3.0

########## Set up dirs #################

#get job ID
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

# enter analysis folder
cd analysis
mkdir -p ${bam_dir}_filtered

if [ "$paired_end" == "yes" ]
then

########## Run #################

#mark duplicates
#requires sorted input - using samtools sort in bsmap step (co-ordinate sorted)
# if co-ordinate sorted then pairs where the mate is unmapped or has secondary alignment are not marked as duplicate
# ASSUME_SORTED=true because sorting performed with samtools but samtools doesnt seem to add this flag to the header
$RUN_PICARD MarkDuplicates \
I=${bam_dir}/${ID}_sorted.bam \
O=${bam_dir}_filtered/${ID}_NoDup.bam \
M=${bam_dir}_filtered/${ID}_NoDupMetrics.txt \
ASSUME_SORT_ORDER=coordinate \
CREATE_INDEX=False \
REMOVE_DUPLICATES=true

# keep properly paired reads using bamtools package
# note that some reads marked as properly paired by bsmap actually map to different chromosomes
bamtools filter \
-isMapped true \
-isPaired true \
-isProperPair true \
-in ${bam_dir}_filtered/${ID}_NoDup.bam \
-out ${bam_dir}_filtered/${ID}_sorted_NoDup_ProPairs.bam

# remove intermediate de-duplicated bam (before proper pairs filter)
rm -v ${bam_dir}_filtered/${ID}_NoDup.bam

#index bam
# index
samtools index ${bam_dir}_filtered/${ID}_sorted_NoDup_ProPairs.bam

echo "done filtering"

elif [ "$paired_end" == "no" ]
then

# remove duplicate
$RUN_PICARD MarkDuplicates \
I=${bam_dir}/${ID}_sorted.bam \
O=${bam_dir}_filtered/${ID}_sorted_NoDup.bam \
M=${bam_dir}_filtered/${ID}_NoDupMetrics.txt \
ASSUME_SORT_ORDER=coordinate \
CREATE_INDEX=False \
REMOVE_DUPLICATES=true

# rename to keep script naming convention consistent
mv ${bam_dir}_filtered/${ID}_sorted_NoDup.bam ${bam_dir}_filtered/${ID}_sorted_NoDup_ProPairs.bam

# index
samtools index ${bam_dir}_filtered/${ID}_sorted_NoDup_ProPairs.bam

echo "done filtering"

else

echo "library type not specified correctly, please indicate yes for PE or no for SE"
exit 1

fi
