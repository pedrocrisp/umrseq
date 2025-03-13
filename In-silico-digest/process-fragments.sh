#!/bin/bash
#PBS -r y
#PBS -m abe
#PBS -M p.crisp@uq.edu.au

########## QC #################
set -xeuo pipefail

echo ------------------------------------------------------
echo -n 'Job is running on node '; cat $PBS_NODEFILE
echo ------------------------------------------------------
echo PBS: qsub is running on $PBS_O_HOST
echo PBS: originating queue is $PBS_O_QUEUE
echo PBS: executing queue is $PBS_QUEUE
echo PBS: working directory is $PBS_O_WORKDIR
echo PBS: execution mode is $PBS_ENVIRONMENT
echo PBS: job identifier is $PBS_JOBID
echo PBS: job name is $PBS_JOBNAME
echo PBS: node file is $PBS_NODEFILE
echo PBS: current home directory is $PBS_O_HOME
echo PBS: PATH = $PBS_O_PATH
echo ------------------------------------------------------

echo working dir is $PWD

#cd into work dir
echo changing to PBS_O_WORKDIR
cd "$PBS_O_WORKDIR"
echo working dir is now $PWD

cd analysis

cat ${output}-tmp/*-cuts.txt > $output/final-cuts.txt
rm -rv $output-tmp

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

Rscript ${scriptdir}/${step}.R \
${output}/$FILTER.tsv \
${output}/$FILTER-50%Ns.tsv \
50

Rscript ${scriptdir}/${step}.R \
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
