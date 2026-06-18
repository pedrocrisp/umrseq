#!/bin/bash
#set -xe
set -xeuo pipefail

############ Change log ###########
# 26 May 2021 Misha Mangila
# Original code. Added help option
#
# 4 July 2021 Misha Mangila
# Added section that will run after the sbatch jobs are run
#
# 20 July 2021 Misha Mangila
# Removed section (commented out)
# Made a few modifications for efficiency
#
# 18 August 2021
# After copying the script, modified script to include seqhax grepbed
# Added section that collates everything after sbatch and run fragment finder
#
# 19 August 2021
# Removed code that splits file into chromosomes. This happens after sbatch in separate script
#
# 19 October 2021
# Rewrote script to find the fragments. Wrote a script to remove fragments that had at least 50% or 80% Ns.
#
#18 Jun 2026 - Yoshi
#Changed -c option from nodes to cpus.
#
################### Help function ###################
Help()
{

echo "This script submits a batch job to PBS in order to simulate the digestion of your chosen genome."
echo
echo "USAGE:"
echo "bash macs_sbatch.sh -g genome.fa -o output -f filter -M motifs.fa -s software_directory -G github_repository -A department -m memory -c number_of_nodes -t walltime"
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
cpus=1
walltime=2:00:00

while getopts ":g:o:f:M:s:G:A:m:c:t:h" option; do
   case $option in
      g) genome=${OPTARG};;
      o) output=${OPTARG};;
      f) filter=${OPTARG};;
      M) motifs=${OPTARG};;
      G) gitdir=${OPTARG};;
      A) account=${OPTARG};;
      m) mem=${OPTARG};;
      c) cpus=${OPTARG};;
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
module load seqtk

# find script to run, makes it file system agnostic #

if
[[ $OSTYPE == darwin* ]]
then
readlink=$(which greadlink)
scriptdir="$(dirname $($readlink -f $0))"
else
scriptdir="$(dirname $(readlink -f $0))"
fi

step=in-silico-digest-s

##### Split genome file by chromosome

bash ${scriptdir}/process-motifs.sh \
-M $motifs \
-o $output \
-s $scriptdir \
-g $genome

#Submit batch job to sbatch
echo "Running the in silico digestion"
genome_size=$output/${output}.chrom.sizes

#### Process motifs file


####

number_of_samples=`wc -l analysis/${output}-tmp/motifs-regex.txt \
| awk '{print $1}'`

sbatch_t=1
if [[ "$number_of_samples" -gt 1 ]]
then

sbatch_t="1-${number_of_samples}"

fi

echo "argument to be passed to sbatch -J is '$sbatch_t'"

mkdir -p logs

timestamp=$(date +%Y%m%d-%H%M%S)

#make trimmgalore logs folder, timestamped
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

script_to_sbatch=${scriptdir}/${step}.sh
cat $script_to_sbatch > ${log_folder}/script.log
cat $0 > ${log_folder}/sbatch_runner.log

post_script_sbatch=${scriptdir}/process-fragments.sh
cat $post_script_sbatch > ${log_folder}/script2.log

sbatch --array $sbatch_t \
-t ${walltime} \
-N 1 \
-c ${cpus} \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--account ${account} \
--job-name digest-$output \
--export LIST=analysis/${output}-tmp/motifs-regex.txt,\
genome_size=${genome_size},\
motifs=$motifs,\
output=$output,\
scriptdir=${scriptdir},\
filter=$filter,\
genome=$( readlink -f $genome ),\
gitdir=${gitdir} \
$script_to_sbatch

echo "Digest done"
