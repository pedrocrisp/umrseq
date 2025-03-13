#!/bin/bash
#set -xe
set -xeuo pipefail

############ Change log ###########
# 26 May 2021 Misha Mangila
# Original code. Added help option
#
# 4 July 2021 Misha Mangila
# Added section that will run after the qsub jobs are run
#
# 20 July 2021 Misha Mangila
# Removed section (commented out)
# Made a few modifications for efficiency
#
# 18 August 2021
# After copying the script, modified script to include seqhax grepbed
# Added section that collates everything after qsub and run fragment finder
#
# 19 August 2021
# Removed code that splits file into chromosomes. This happens after qsub in separate script
#
# 19 October 2021
# Rewrote script to find the fragments. Wrote a script to remove fragments that had at least 50% or 80% Ns.

################### Help function ###################
Help()
{

echo "This script submits a batch job to PBS in order to simulate the digestion of your chosen genome."
echo
echo "USAGE:"
echo "bash macs_qsub.sh -g genome.fa -o output -f filter -M motifs.fa -s software_directory -G github_repository -A department -m memory -c number_of_nodes -t walltime"
echo
echo "The motifs.fa file contains all recognition sites of the enzymes that you wish to apply, with the enzyme names."
echo
echo "The filter is the minimum length of the fragment that is accepted by the filter."
echo
echo "Default memory usage is 20GB, default CPU usage is 1 CPU and default walltime is 2 hours."
echo

}

############### Options with defaults ###############
mem=20
nodes=1
walltime=2:00:00

while getopts ":g:o:f:M:s:G:A:m:c:t:h" option; do
   case $option in
      g) genome=${OPTARG};;
      o) output=${OPTARG};;
      f) filter=${OPTARG};;
      M) motifs=${OPTARG};;
      s) softwaredir=${OPTARG};;
      G) gitdir=${OPTARG};;
      A) account=${OPTARG};;
      m) mem=${OPTARG};;
      c) nodes=${OPTARG};;
      t) walltime=${OPTARG};;
      h) # display Help
         Help
         exit;;
     \?) # incorrect option
         echo "Error: Invalid option"
         exit;;
   esac
done

#####################################################
################### Main function ###################
#####################################################

###################### Modules ######################
#requires seqkit

# find script to run, makes it file system agnostic #

if
[[ $OSTYPE == darwin* ]]
then
readlink=$(which greadlink)
scriptdir="$(dirname $($readlink -f $0))"
else
scriptdir="$(dirname $(readlink -f $0))"
fi

step=in-silico-digest

##### Split genome file by chromosome

bash ${scriptdir}/process-motifs.sh \
-M $motifs \
-o $output \
-s $scriptdir \
-S $softwaredir \
-g $genome

#Submit batch job to qsub
echo "Running the in silico digestion"
genome_size=$output/${output}.chrom.sizes

#### Process motifs file


####

number_of_samples=`wc -l analysis/${output}-tmp/motifs-regex.txt \
| awk '{print $1}'`

qsub_t=1
if [[ "$number_of_samples" -gt 1 ]]
then

qsub_t="1-${number_of_samples}"

fi

echo "argument to be passed to qsub -J is '$qsub_t'"

mkdir -p logs

timestamp=$(date +%Y%m%d-%H%M%S)

#make trimmgalore logs folder, timestamped
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

script_to_qsub=${scriptdir}/${step}.sh
cat $script_to_qsub > ${log_folder}/script.log
cat $0 > ${log_folder}/qsub_runner.log

post_script_qsub=${scriptdir}/process-fragments.sh
cat $post_script_qsub > ${log_folder}/script2.log

qsub -J $qsub_t \
-l walltime=${walltime},nodes=1:ppn=${nodes},mem=${mem}gb \
-o ${log_folder}/${step}_o^array_index^ \
-e ${log_folder}/${step}_e^array_index^ \
-A ${account} \
-N digest-$output \
-Wblock=true \
-v LIST=analysis/${output}-tmp/motifs-regex.txt,\
genome_size=${genome_size},\
motifs=$motifs,\
output=$output,\
scriptdir=${scriptdir},\
filter=$filter,\
genome=$( readlink -f $genome ),\
gitdir=${gitdir} \
$script_to_qsub

qsub \
-l walltime=${walltime},nodes=1:ppn=${nodes},mem=${mem}gb \
-o ${log_folder}/${step}_last_o \
-e ${log_folder}/${step}_last_e \
-A ${account} \
-N post-digest-$output \
-Wblock=true \
-v LIST=analysis/${output}-tmp/motifs-regex.txt,\
genome_size=${genome_size},\
motifs=${motifs},\
output=${output},\
scriptdir=${scriptdir},\
filter=${filter},\
genome=$( readlink -f $genome ),\
softwaredir=${softwaredir},\
step=${step} \
$post_script_qsub

echo "Digest done"
