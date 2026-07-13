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
module purge
module load bedtools/2.31.1-gcc-14.2.0 \
seqtk/1.5-gcc-14.2.0 \
r/4.4.2

#cd analysis
DIG=$(basename $output)

#consolidate cut sites across all recognition motifs:
ls ${output}-tmp/*-cuts.txt > /dev/null 2>&1 || { echo "ERROR: no cuts files found in ${output}-tmp/" >&2; exit 1; }
cat ${output}-tmp/*-cuts.txt > $output/final-cuts.txt

#rm -rv $output-tmp

echo "Filtering fragments by size"
#Organise cut sites into fragments and filter frags >100 bp
python3 ${scriptdir}/find_fragments.py \
$output/final-cuts.txt \
$filter ${output}/${DIG}.chrom.sizes \
${output}/${DIG}

FILTER=${DIG}-fragments-filtered
echo -e "Location\tLength\tnum_Ns" \
> ${output}/$FILTER.tsv

sed 1d ${output}/${DIG}-fragments-filtered.txt \
> ${output}/$FILTER.bed

#retrieve sequence matching each surviving fragment
bedtools getfasta \
-fi $genome \
-bed ${output}/$FILTER.bed \
-fo ${output}/$FILTER.fa || \
${softwaredir}/bedtools getfasta \
-fi $genome \
-bed ${output}/$FILTER.bed \
-fo ${output}/$FILTER.fa

echo "Filtering fragments by percentage of N"
#count of N (undefined) bases in each fragment (-f 9)
seqtk comp \
${output}/$FILTER.fa \
| cut -f 1,2,9 \
>> ${output}/$FILTER.tsv

#filter to remove fragments with over 50% N
Rscript ${scriptdir}/in-silico-digest.R \
${output}/$FILTER.tsv \
${output}/$FILTER-50%Ns.tsv \
50

Rscript ${scriptdir}/in-silico-digest.R \
${output}/$FILTER.tsv \
${output}/$FILTER-80%Ns.tsv \
80

echo "Converting output to BED"
for i in ${output}/*-filtered-*%Ns.tsv
do
  BED=`echo $i | sed s/\.tsv/.bed/`
  TEMP=`echo $i | sed s/\.tsv/_tmp.bed/`
  sed 1d $i > $TEMP
  tr ":" "\t" < $TEMP | tr "-" "\t" > $BED
done

#rm -rv ${output}/*_tmp.bed
echo "In silico digestion complete"
