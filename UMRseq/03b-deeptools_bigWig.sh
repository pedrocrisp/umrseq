#!/bin/bash -l
#SBATCH --job-name bigWig
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
# conda env with deeptools and mosdepth installed
conda activate $conda_enviro

########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {PBS_ARRAY_INDEX} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

#make adaligned folder bsmaped
cd analysis
mkdir -p ${bam_dir}_bigWigs_deeptools
mkdir -p ${bam_dir}_insert_metrics
mkdir -p ${bam_dir}_mosdepth
mkdir -p ${bam_dir}_100bp_tiles

########## Run #################
# make normalised bigWigs
# uising --extendReads as suggested for contiguous mapping data like ChIP to map whole of PE frag
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_bigWigs_deeptools/${ID}.bw \
--binSize 10 \
--normalizeUsing CPM \
--extendReads \
-p 2

# also make megabase coverage plots to look at any genomie-wide trimmed_align_bowtie2_bigWigs_de
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_100bp_tiles/${ID}.bedgraph \
--binSize 100 \
--normalizeUsing CPM \
--outFileFormat bedgraph \
-p 2

# also make megabase coverage plots to look at any genomie-wide trimmed_align_bowtie2_bigWigs_deeptools
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_bigWigs_deeptools/${ID}.bedgraph \
--binSize 1000000 \
--normalizeUsing CPM \
--outFileFormat bedgraph \
-p 2

# also make Kb coverage plots to look at plamids in transgeen free exp trimmed_align_bowtie2_bigWigs_deeptools
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_bigWigs_deeptools/${ID}_1000bin.bedgraph \
--binSize 1000 \
--normalizeUsing CPM \
--outFileFormat bedgraph \
-p 2

# make 500 bp bin with cumulative coverage and average coverage stats using mosdepth
# -n dont output per-base depth. skipping this output will speed execution substantially. prefer quantized or thresholded values if possible.
# --fast-mode dont look at internal cigar operations or correct mate overlaps (recommended for most use-cases).
# --by 500 500bp bins
# prefix
# bam

mosdepth \
-n \
--fast-mode \
--by 500 \
${bam_dir}_mosdepth/${ID} \
$bam_dir/${ID}_sorted.bam

# # also make Kb coverage plots to look at plamids in transgeen free exp trimmed_align_bowtie2_bigWigs_deeptools
# # this is normalised to genome size so will calculate x-coverage essentially?
# # sorghum 708863705
# bamCoverage \
# --bam $bam_dir/${ID}_sorted.bam \
# -o ${bam_dir}_bigWigs_deeptools/${ID}_1000bin_RPGC.bedgraph \
# --binSize 1000 \
# --normalizeUsing RPGC \
# --effectiveGenomeSize $RPGC \
# --outFileFormat bedgraph \
# -p 2# 

############ get frag sizes ##############
# get frag sizes to check level of tagmentation using picard
# path to call picard jar - eg  - "/home/uqpcrisp/software/picard.jar"

########## Modules #################
module load java/11.0.18
# picard needs R
module load r/4.1.0-foss-2021a

java -jar ~/software/picard.jar CollectInsertSizeMetrics \
I=$bam_dir/${ID}_sorted.bam \
O=${bam_dir}_insert_metrics/${ID}_insert_size_metrics.txt \
H=${bam_dir}_insert_metrics/${ID}_insert_size_histogram.pdf \
M=0.5

echo finished summarising