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

TEMP=$((dirname $genome)/${output}-tmp)
OUT=$((dirname $genome)/{$output})

mkdir -p ${TEMP}
mkdir -p ${OUT}

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

seqtk comp $genome | \
cut -f 1-2 \
> ${TEMP}/$output.fasta.chrom.sizes
# sort
sort -k1,1 -k2,2n \
${TEMP}/${output}.fasta.chrom.sizes \
> ${OUT}/${output}.chrom.sizes

rm ${TEMP}/${output}.fasta.chrom.sizes

grep -v ">" $motifs \
| sed "s/$/\t+/" \
> ${TEMP}/motifs.txt

seqkit seq -rp $motifs \
| grep -v ">" \
| sed "s/$/\t-/" \
>> ${TEMP}/motifs.txt

python3 ${scriptdir}/convert_bases.py \
${TEMP}/motifs.txt \
> ${TEMP}/motifs-regex.txt

echo -e "seqID\tpatternName\tpattern\tstrand\tstart\tend\tmatched" \
> ${OUT}/digest-template.txt

echo -e "Chromosome\tStart\tEnd\tLength" \
> ${OUT}/fragment-template.txt

conda deactivate
