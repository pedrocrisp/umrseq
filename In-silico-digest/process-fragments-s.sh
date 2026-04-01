#!/bin/bash
#SBATCH --requeue
#SBATCH --partition=general

########## QC #################
set -xeuo pipefail

echo ------------------------------------------------------
echo SBATCH: working directory is $SLURM_SUBMIT_DIR
echo SBATCH: job identifier is $SLURM_JOBID
echo ------------------------------------------------------

echo working dir is $PWD

#cd into work dir
echo changing to SLURM_SUBMIT_DIR
cd "$SLURM_SUBMIT_DIR"
echo working dir is now $PWD

# Load modules
module load bedtools
module load r/4.4.2-gfbf-2024a
module load seqtk/1.3-gcc-11.3.0

cd analysis

cat ${output}-tmp/*-cuts.txt > $output/final-cuts.txt
#rm -rv $output-tmp

python3 ${scriptdir}/find_fragments.py \
$output/final-cuts.txt \
$filter $output/$output.chrom.sizes \
$output/$output

FILTER=${output}-fragments-filtered
echo -e "Location\tLength\tnum_Ns" \
> ${output}/$FILTER.tsv

sed 1d ${output}/${output}-fragments-filtered.txt \
> ${output}/$FILTER.bed

bedtools getfasta \
-fi $genome \
-bed ${output}/$FILTER.bed \
-fo ${output}/$FILTER.fa || \
${softwaredir}/bedtools getfasta \
-fi $genome \
-bed ${output}/$FILTER.bed \
-fo ${output}/$FILTER.fa

seqtk comp \
${output}/$FILTER.fa \
| cut -f 1,2,9 \
>> ${output}/$FILTER.tsv

Rscript ${scriptdir}/in-silico-digest.R \
${output}/$FILTER.tsv \
${output}/$FILTER-50%Ns.tsv \
50

Rscript ${scriptdir}/in-silico-digest.R \
${output}/$FILTER.tsv \
${output}/$FILTER-80%Ns.tsv \
80

for i in ${output}/*-filtered-*%Ns.tsv
do
  BED=`echo $i | sed s/\.tsv/.bed/`
  TEMP=`echo $i | sed s/\.tsv/_tmp.bed/`
  sed 1d $i > $TEMP
  tr ":" "\t" < $TEMP | tr "-" "\t" > $BED
done

rm -rv ${output}/*_tmp.bed
