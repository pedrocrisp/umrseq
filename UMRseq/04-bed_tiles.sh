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
# *** bedtools needs updatign to gcc-12 or 13 in 2026 ***
module load bedtools/2.30.0-gcc-11.3.0
# module load bedtools/2.30.0-gcc-10.3.0
########## Set up dirs #################

#get job ID
#use sed, -n supression pattern space, then 'p' to print item number {SLURM_ARRAY_TASK_ID} eg 2 from {list}
ID="$(/bin/sed -n ${SLURM_ARRAY_TASK_ID}p ${LIST})"

echo sample being mapped is $ID

#make adaligned folder bsmaped
cd analysis
mkdir -p tmp_beds_for_tiles
mkdir -p tiles

########## Run #################

# bam_dir="trimmed_align_bowtie2"
# ID="UMR_McrBC_MF_90"
# chrom_sizes="/90days/uqpcrisp/tmp_refseqs/Nbenth/NbLab330.genome.chrom.sizes"
# reference_tile_file="/90days/uqpcrisp/tmp_refseqs/Nbenth/sites/NbLab330.genome_100bp_tiles.bed"
# reference_tile_file=~/refseqs/maize/sites/Zea_mays.AGPv4.dna.toplevel_100bp_tiles_sorted.bed
# CPM_filter_UMRs=0.5

# reference tile file format:
# head Sbicolor_454_v3.0.1_100bp_tiles.sorted.bed
# Chr01   0       100     Chr01:0-100
# Chr01   100     200     Chr01:100-200

# NOTE: we realised this approach has 2 shortcomings
# 1. it doesnt remove overlapping portions of PE reads which will have double coverage
# 2. it doesnt extend reads to represent the whole fragement
# consider improving the code to deal with these issues...

# bedgraph
# -dz 0-based co-ordinates, reporting per base
# not reporting bases with 0 coverage
bedtools genomecov -dz -ibam $bam_dir/${ID}_sorted.bam -g $chrom_sizes | \
awk -F$"\\t" -v s=1 'BEGIN {OFS = FS} {print $1, $2, $2+s, $3}' - | \
LC_COLLATE=C sort -k1,1 -k2,2n - > tmp_beds_for_tiles/${ID}_sorted.bed

#### summarise coverage into 100bp tiles
# previously I used 5' coverage only and also the -a option to includes 0 counts, but not sure this is useful anymore...

# use closest to overlap with 100bp tile then summarise with groupby
bedtools closest -t all -a tmp_beds_for_tiles/${ID}_sorted.bed -b $reference_tile_file |
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
#### merge bookended UMRs
# implemented a CPM filter, but not sure if we will use this filtered file or not - keeping for now
awk -v CPM_filter_UMRs=$CPM_filter_UMRs '$4 > CPM_filter_UMRs' tiles/${ID}_100bp_CPM.bed |
bedtools merge -c 4 -o sum -i - > tiles/${ID}_100bp_CPM_${CPM_filter_UMRs}_UMRs.bed

# uncomment once script dev is finished to delete the large intermediate bed file
# rm -rv tmp_beds_for_tiles

echo finished summarising
