#!/bin/bash -l
#SBATCH --job-name fastqc
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
module load bedtools/2.30.0-gcc-10.3.0
########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

#make adaligned folder bsmaped
cd analysis
mkdir -p bedgraphs
mkdir -p tiles

########## Run #################

# bam_dir="trimmed_align_bowtie2"
# ID="UMR_McrBC_MF_90"
# chrom_sizes="/90days/uqpcrisp/tmp_refseqs/Nbenth/NbLab330.genome.chrom.sizes"
# reference_tile_file="/90days/uqpcrisp/tmp_refseqs/Nbenth/sites/NbLab330.genome_100bp_tiles.bed"
# CPM_filter_UMRs=0.5

# bedgraph
bedtools genomecov -bgd -ibam $bam_dir/${ID}_sorted.bam -g $chrom_sizes | LC_COLLATE=C sort -k1,1 -k2,2n - > bedgraphs/${ID}_sorted.bedgraph

#### summarise coverage into 100bp tiles
# previously I used 5' coverage only and also the -a option to includes 0 counts, but not sure this is useful anymore...

# use closest to overlap with 100bp tile then summarise with groupby
bedtools closest -t all -a bedgraphs/${ID}_sorted.bedgraph -b $reference_tile_file |
bedtools groupby -g 5,6,7 -c 4 > tiles/${ID}_100bp.bed

#### normalise to CPM
# norm factor (CPM) 4 decimal places
norm_factor=`awk -F$"\\t" 'BEGIN {OFS = FS} {sum1 += $4+0} END {print sum1/1000000}' tiles/${ID}_100bp.bed`
echo norm factor $norm_factor
#
awk -F$"\\t" -v norm_factor=$norm_factor 'BEGIN {OFS = FS} {
  print $1, $2, $3, $4/norm_factor
}' "tiles/${ID}_100bp.bed" > tiles/${ID}_100bp_CPM.bed

#### filter
awk -v CPM_filter_UMRs=$CPM_filter_UMRs '$4 > CPM_filter_UMRs' tiles/${ID}_100bp_CPM.bed |
bedtools merge -c 4 -o sum -i - > tiles/${ID}_100bp_CPM_${CPM_filter_UMRs}_UMRs.bed

#### merge to call UMRs

echo finished summarising
