#!/bin/bash

while getopts ":M:o:s:S:g:e:h" option; do
   case $option in
      M) motifs=${OPTARG};;
      o) output=${OPTARG};;
      s) scriptdir=${OPTARG};;
      g) genome=${OPTARG};;
      e) env=${OPTARG};;
     \?) # incorrect option
         echo "Error: Invalid option"
         exit;;
   esac
done

mkdir -p ${output}-tmp
mkdir -p ${output}

TEMP=${output}-tmp
OUT=${output}
DIG=$(basename $output)

module load miniconda3/23.9.0-0 seqtk/1.5-gcc-14.2.0
source $EBROOTMINICONDA3/etc/profile.d/conda.sh

if ! conda activate "$env" 2>/dev/null; then
  echo "Error: Failed to activate conda environment '$env'. Available environments:" >&2
  conda env list || true
  exit 1
fi
#csplit -s -z \
#-f analysis/${output}-tmp/Chr \
#$genome \
#'/>/' '{*}'
touch ${TEMP}/${DIG}.fasta.chrom.sizes
touch ${OUT}/${DIG}.chrom.sizes

seqtk comp $genome | \
cut -f 1-2 \
> ${TEMP}/${DIG}.fasta.chrom.sizes
# sort
sort -k1,1 -k2,2n \
${TEMP}/${DIG}.fasta.chrom.sizes \
> ${OUT}/${DIG}.chrom.sizes

rm ${TEMP}/${DIG}.fasta.chrom.sizes

touch ${TEMP}/motifs.txt

grep -v ">" $motifs \
| sed "s/$/\t+/" \
> ${TEMP}/motifs.txt

seqkit seq -t DNA -rp $motifs \
| grep -v ">" \
| sed "s/$/\t-/" \
>> ${TEMP}/motifs.txt

touch ${TEMP}/motifs-regex.txt

python3 ${scriptdir}/convert_bases.py \
${TEMP}/motifs.txt \
> ${TEMP}/motifs-regex.txt

touch ${OUT}/digest-template.txt
touch ${OUT}/fragment-template.txt

echo -e "seqID\tpatternName\tpattern\tstrand\tstart\tend\tmatched" \
> ${OUT}/digest-template.txt

echo -e "Chromosome\tStart\tEnd\tLength" \
> ${OUT}/fragment-template.txt

conda deactivate
