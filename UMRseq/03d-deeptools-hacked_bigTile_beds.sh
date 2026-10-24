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

conda activate $conda_enviro

########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {PBS_ARRAY_INDEX} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

# make folders
cd analysis
mkdir -p ${bam_dir}_hacked_${res}bp_tiles

########## Run #################

## should we skip zeros when using bamCoverage???
## skipping zeros would make files much smaller
## skipping zeros might impact coverage comparsions between samples depending on tool used for making comparisons.

# also make megabase coverage plots to look at any genomie-wide trimmed_align_bowtie2_bigWigs_deeptools
# --blackListFileName $blacklist is not used in this step as behavour is untested - would it skip an entire Mb tile if it had a 100bp of blacklisted bps???
bamCoverage \
--bam $bam_dir/${ID}_sorted.bam \
-o ${bam_dir}_hacked_${res}bp_tiles/${ID}_${res}bp.bed \
--binSize ${res} \
--normalizeUsing CPM \
--extendReads \
--outFileFormat bedgraph \
-p 2

echo finished summarising