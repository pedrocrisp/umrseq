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

mkdir -p analysis/${output}-tmp
mkdir -p analysis/{$output}

module load miniconda3/23.9.0-0 seqtk
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
> analysis/${output}-tmp/$output.fasta.chrom.sizes
# sort
sort -k1,1 -k2,2n \
analysis/${output}-tmp/${output}.fasta.chrom.sizes \
> analysis/$output/${output}.chrom.sizes

rm analysis/${output}-tmp/${output}.fasta.chrom.sizes

grep -v ">" $motifs \
| sed "s/$/\t+/" \
> analysis/${output}-tmp/motifs.txt

seqkit seq -rp $motifs \
| grep -v ">" \
| sed "s/$/\t-/" \
>> analysis/${output}-tmp/motifs.txt

python3 ${scriptdir}/convert_bases.py \
analysis/${output}-tmp/motifs.txt \
> analysis/${output}-tmp/motifs-regex.txt

echo -e "seqID\tpatternName\tpattern\tstrand\tstart\tend\tmatched" \
> analysis/$output/digest-template.txt

echo -e "Chromosome\tStart\tEnd\tLength" \
> analysis/$output/fragment-template.txt

conda deactivate
