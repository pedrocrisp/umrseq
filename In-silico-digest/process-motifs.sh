#!/bin/bash

while getopts ":M:o:s:S:g:h" option; do
   case $option in
      M) motifs=${OPTARG};;
      o) output=${OPTARG};;
      s) scriptdir=${OPTARG};;
      g) genome=${OPTARG};;
     \?) # incorrect option
         echo "Error: Invalid option"
         exit;;
   esac
done

mkdir -p analysis/${output}-tmp
mkdir -p analysis/$output

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
