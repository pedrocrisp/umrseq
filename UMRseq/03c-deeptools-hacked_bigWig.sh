#!/bin/bash -l
#SBATCH --job-name bigWig
#SBATCH --requeue
#SBATCH --partition=general

########## Versions #################
# it is recommended to use the deeptool-hacked script and install deeptool hacked (ie this script!)

# this version is the original that was run with the standard install of deeptools which merges adjacent tiles with the same value (bedgraph style)
# the deeptools-hacked script was designed to run the hacked version of deep tools which does not merge adjacent tiles even if they are the same value, this works better with downstream code that expects 100 bp tiles only
# Both version of the deeptools script can run with a normal or a hacked deeptools install, so check which conda env you are using and whether you hacked deeptools
# If you are only using deeptools to mkae files to visualise in IGV then it doesnt matter if you are using the hacked or the normal deeptools
# If you are using deeptools to make eg bigwig or bed files to look at read coverage, then it *might* matter which version you are using depending how you are averaging tiles or comparing tiles between samples - in this case use the hacked install

# tl;dr
# if making IGV files only and you aready used normal deeptools install and script, this is fine
# if using deeptools outputs (ie this does not apply to bams) to plot coverage, compare samples or compare tiles, then use hacked-deeptools

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
# conda env with deeptools-hacked and mosdepth installed
# conda create deeptools-hacked python=3.7
# conda activate deeptools-hacked
# conda install -c bioconda mosdepth
# conda install -c bioconda deeptools=3.5.1
# in "writeBedGraph.py"
# eg found in: ~/miniconda3/pkgs/deeptools-3.5.1-pyhdfd78af_1/site-packages/deeptools
# uncomment:
#  # uncomment these lines if fixed step bedgraph is required
#            if not np.isnan(value):
#                writeStart = start + tileIndex * self.binLength
#                writeEnd  =  min(writeStart + self.binLength, end)
#                _file.write(line_string.format(chrom, writeStart,
#                                               writeEnd, value))
#            continue
#
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
mkdir -p ${bam_dir}_hacked_bw_deeptools
mkdir -p ${bam_dir}_insert_metrics
mkdir -p ${bam_dir}_mosdepth
mkdir -p ${bam_dir}_hacked_100bp_tiles
mkdir -p ${bam_dir}_hacked_big_tiles

# NOTE: do we need to clip overlapping reads?
# compare to bams and see what the script actually does

########## Run #################
# make normalised bigWigs
# using --extendReads as suggested for contiguous mapping data like ChIP to map whole of PE frag
# try making 1bp bins for higher res coverage calculation 
# if we are going to use the .bw for pulling coverage, this may increase precision eg in correlations between samples?

## should we skip zeros when using bamCoverage???
## skipping zeros would make files much smaller
## skipping zeros might impact coverage comparsions between samples depending on tool used for making comparisons...

if [ "$highres" == "highres" ]
then
echo making high-res 1bp resolution bigwig files **caution** these are big files
# 1 bp bins for higher res
# use for measuring and comparing coverage
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_bw_deeptools/${ID}.1.bw \
--binSize 1 \
--normalizeUsing CPM \
--extendReads \
--blackListFileName $blacklist \
-p 2
fi

# 10 bp bins for smaller files
# 10x smaller than the 1bp files
# this size is probably enough if all we want to do is visualise in igv 
# also probably sufficient res for most coverage comparisons
## (use for IGV)
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_bw_deeptools/${ID}.10.bw \
--binSize 10 \
--normalizeUsing CPM \
--extendReads \
--blackListFileName $blacklist \
-p 2

# also make 100bp tile coverage plots to compare to other 100bp tile data (eg WGBS)
# output as bed file
# skip zeros (can impute later if needed)
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_100bp_tiles/${ID}.bed \
--binSize 100 \
--normalizeUsing CPM \
--extendReads \
--skipNAs \
--outFileFormat bedgraph \
--blackListFileName $blacklist \
-p 2

# also make megabase coverage plots to look at any genomie-wide trimmed_align_bowtie2_bigWigs_deeptools
# --blackListFileName $blacklist is not used in this step as behavour is untested - would it skip an entire Mb tile if it had a 100bp of blacklisted bps???
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_big_tiles/${ID}_1Mb.bed \
--binSize 1000000 \
--normalizeUsing CPM \
--extendReads \
--outFileFormat bedgraph \
-p 2

# also make Kb coverage plots to look at plamids in transgeen free exp trimmed_align_bowtie2_bigWigs_deeptools
# --blackListFileName $blacklist is not used in this step as behavour is untested - would it skip an entire Mb tile if it had a 100bp of blacklisted bps???
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_big_tiles/${ID}_1000bin.bed \
--binSize 1000 \
--normalizeUsing CPM \
--extendReads \
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
# module update 26/4/26
# module load java/11.0.18
# module load java/11.0.27

# picard needs R
# loading this R module also loads java java/17.0.15
module load r/4.4.2-gfbf-2024a

java -jar ~/software/picard/build/libs/picard.jar CollectInsertSizeMetrics \
I=$bam_dir/${ID}_sorted.bam \
O=${bam_dir}_insert_metrics/${ID}_insert_size_metrics.txt \
H=${bam_dir}_insert_metrics/${ID}_insert_size_histogram.pdf \
CREATE_INDEX=FALSE \
M=0.5

echo finished summarising
