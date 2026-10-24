#!/bin/bash
#set -xe
set -xeuo pipefail

step=macs2

############ Change log ###########
# 26 May 2021 Misha Mangila
# Original code. Added help option
#
#
#
#

##################### Help ##########
Help()
{

echo "This script submits a SLURM array job to run MACS2 for peak calling before or after deduplication."
echo
echo "USAGE:"
echo "bash macs2_sbatch.sh -i sample_list.txt -r reads_folder -A AccountString -s genome_size
[-m memory] [-c number_of_cores] [-t walltime] [-p paired_end] [-C control_prefix] [-D nomodel] [-B] [-f]"
echo
echo "Required:"
echo "-i sample list, one sample prefix per line"
echo "-r reads (bam) folder, relative to analysis/"
echo "-A AccountString (your SLURM account), there is no default."
echo "-s effective genome size, in scientific or decimal notation (eg 2.1e9), there is no default."
echo
echo "Optional:"
echo "-p paired_end, 'yes' for paired-end reads and 'no' for single-end reads. Default: yes"
echo "-m memory in GB. Default: 20"
echo "-c number of CPUs. Default: 1"
echo "-t walltime. Default: 2:00:00"
echo "-C <control_prefix> to use a control sample. Default: no control."
echo "-D nomodel to disable MACS2 fragment size modelling. Default: model (no effect with paired-end BAMPE)"
echo "-B to activate broad peak analysis"
echo "-f if the samples have been filtered using the script 02b-filter-dups_sbatch.sh"

}

#### Defaults ######
mem=20
cores=1
walltime=2:00:00
paired_end=yes
broad=no
filter=no
model=yes
control=no
# required args - no defaults, checked below
sample_list=""
reads_folder=""
account=""
genome_size=""

while getopts ":i:r:o:A:m:c:t:s:p:C:D:Bfh" option; do
   case $option in
      i) sample_list=${OPTARG};;
      r) reads_folder=${OPTARG};;
      o) output=${OPTARG};;
      A) account=${OPTARG};;
      m) mem=${OPTARG};;
      c) cores=${OPTARG};;
      t) walltime=${OPTARG};;
      s) genome_size=${OPTARG};;
      p) paired_end=${OPTARG};;
      C) control=${OPTARG};;
      D) model=${OPTARG};;
      B) broad=yes;;
      f) filter=yes;;
      h) # display Help
         Help
         exit;;
     \?) # incorrect option
         echo "Error: Invalid option"
         exit;;
   esac
done

# removed arg
#  D) conda_enviro=${OPTARG};;


#define stepo in the pipeline - should be the same name as the script
step=macs2

############## Setup ###############

errors=0

if [[ ! $sample_list ]]
then
errors=$(($errors + 1))
echo "ERROR: No sample list"
fi

if [[ ! $account ]]
then
errors=$(($errors + 10))
echo "ERROR: No account string"
fi

if [[ ! $reads_folder ]]
then
errors=$(($errors + 100))
echo "ERROR: No reads folder"
fi

if [[ ! $genome_size ]]
then
errors=$(($errors + 1000))
echo "ERROR: No genome size"
fi

if [[ $errors -gt 0 ]]
then
echo "Proper usage:"
echo
Help
exit $errors
fi

echo "Running MACS2"
cat $sample_list

number_of_samples=`wc -l $sample_list | awk '{print $1}'`

sbatch_t=1
if [[ "$number_of_samples" -gt 1 ]]
then

sbatch_t="1-${number_of_samples}"

fi

echo "argument to be passed to sbatch -J is '$sbatch_t'"

mkdir -p logs

timestamp=$(date +%Y%m%d-%H%M%S)
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

scriptdir="$(dirname $(readlink -f $0))"
script_to_sbatch=${scriptdir}/${step}.sh
cat $script_to_sbatch > ${log_folder}/script.log
cat $0 > ${log_folder}/sbatch_runner.log

#submit sbatch and pass args
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the array list and the dir structures
sbatch --array $sbatch_t \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task ${cores} \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--export LIST=${sample_list},paired_end=$paired_end,genome_size=$genome_size,broad=$broad,reads_folder=${reads_folder},filter=$filter,control=${control},model=${model} \
--account $account \
$script_to_sbatch

# ,conda_enviro=${conda_enviro}

