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
#Changed -c option from nodes to cpus. By default seqtk (in process-motifs.sh) uses 4 threads. 
#Changed process-motifs.sh invocation to be an sbatch submission, since previously it was ran in the 
#login node. Now it is submitted and the following job is dependent on the first job completion.
#Then changed the last sbatch submission to run with 1 core per array,since seqhax cannot perform 
#multithreaded operations.
#Added a genome compression check, since I usually have it stored compressed.
#
################### Help function ###################
Help()
{

echo "This script submits a batch job to PBS in order to simulate the digestion of your chosen genome."
echo
echo "USAGE:"
echo "bash macs_sbatch.sh -g genome.fa -o output -f filter -M motifs.fa -s software_directory -G github_repository -A department -m memory -c number_of_cpu -t walltime -e digestEnv"
echo
echo "The motifs.fa file contains all recognition sites of the enzymes that you wish to apply, with the enzyme names."
echo
echo "The filter is the minimum length of the fragment that is accepted by the filter."
echo
echo "Input genome must be an uncompressed FASTA file"
echo
echo "Default memory usage is 20GB, default CPU usage is 1 CPU (no multi-threading) and default walltime is 2 hours."
echo

}

############### Options with defaults ###############
mem=20
cpus=1
walltime=2:00:00
env=digestEnv

while getopts ":g:o:f:M:G:A:m:c:t:e:h" option; do
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
      e) env=${OPTARG};;
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

if [[ $OSTYPE == darwin* ]]; then
readlink=$(which greadlink)
scriptdir="$(dirname $($readlink -f $0))"
else
scriptdir="$(dirname $(readlink -f $0))"
fi

# require genome variable to be set first
if [[ -z "${genome:-}" ]]; then
  echo "ERROR: genome file not specified. Use -g <genome.fa>" >&2
  exit 1
fi

case "$genome" in
    *.gz)
    echo "Genome file is gzip compressed. Decompressing..."
    gunzip -k "$genome" || { echo "ERROR: Failed to decompress $genome" >&2; exit 1; }
    genome="${genome%.gz}"
    echo "Decompressed to: $genome"
    ;;
   *.zip)
    echo "Genome file is .zip compressed. Decompressing..."
    unzip -n "$genome" || { echo "ERROR: Failed to decompress $genome" >&2; exit 1; }
    genome="${genome%.zip}"
    echo "Decompressed to: $genome"
    ;;
  *)
    ;;  # nothing to do for uncompressed filenames
esac

echo "Running the in silico digestion"
##### Split genome file by chromosome
pre_jobid=$(sbatch --parsable -t 1 \
--mem 5gb \
--cpus-per-task 1 \
--export=ALL \
--wrap="bash ${scriptdir}/process-motifs.sh \
-M $motifs \
-o $output \
-s $scriptdir \
-g $genome \
-e $env") 

if [[ -z "$pre_jobid" ]]; then 
   echo "ERROR: failed to submit preprocessing job" >&2 
   exit 1 
fi 
echo "Submitted preprocessing job: $pre_jobid"

echo "Waiting for preprocess job $pre_jobid to finish..." 
while squeue -j "$pre_jobid" >/dev/null 2>&1; 
   do sleep 30 
done

if command -v sacct >/dev/null 2>&1; then 
   state=$(sacct -j "$pre_jobid" --format=State --noheader | head -n 1 | awk '{print $1}') 
      if [[ "$state" != "COMPLETED" ]]; then
         echo "Preprocessing job $pre_jobid did not complete successfully: $state" >&2
         exit 1
      fi
else echo "sacct not available; assuming preprocess finished successfully (monitor manually if needed)" fi
fi

TEMP=${output}-tmp
OUT=${output}
DIG=$(basename $output)

#${OUT}/digest-template.txt
#${OUT}/fragment-template.txt

#bash ${scriptdir}/process-motifs.sh \
#-M $motifs \
#-o $output \
#-s $scriptdir \
#-g $genome

#Submit batch job to sbatch
genome_size=${OUT}/${DIG}.chrom.sizes

#### Process motifs file
if [[ -z "$number_of_samples" || "$number_of_samples" -lt 1 ]]; 
   then echo "No samples found in ${TEMP}/motifs-regex.txt" >&2 
   exit 1 
fi

####
step=in-silico-digest-s

number_of_samples=`wc -l ${TEMP}/motifs-regex.txt \
| awk '{print $1}'`

sbatch_t=1
if [[ "$number_of_samples" -gt 1 ]]
   then sbatch_t="1-${number_of_samples}"
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

sbatch --dependency=afterok:${pre_jobid} \
--array $sbatch_t \
-t ${walltime} \
-N 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--account ${account} \
--job-name digest-$output \
--export=ALL,LIST=${TEMP}/motifs-regex.txt,\
genome_size=${genome_size},\
env=$env,\
motifs=$motifs,\
output=$output,\
scriptdir=${scriptdir},\
filter=$filter,\
genome=$( readlink -f $genome ),\
gitdir=${gitdir} \
$script_to_sbatch

echo "Digest done"
