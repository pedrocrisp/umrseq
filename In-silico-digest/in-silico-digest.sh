#!/bin/bash
#PBS -N digestion
#PBS -r y
#PBS -m abej
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
echo PBS: array_ID is ${PBS_ARRAY_INDEX}
echo ------------------------------------------------------

echo working dir is $PWD

#cd into work dir
echo changing to PBS_O_WORKDIR
cd "$PBS_O_WORKDIR"
echo working dir is now $PWD

###### Modules ################
# Requires seqhax

###### Set up directories #####
LINE="$(/bin/sed -n ${PBS_ARRAY_INDEX}p ${LIST})"
PATTERN=$(echo $LINE | cut -d " " -f 1)
REGEX=$(echo $LINE | cut -d " " -f 2)
STRAND=$(echo $LINE | cut -d " " -f 3)

echo sample is being digested by $PATTERN

cd analysis

seqhax grepbed -p $REGEX $genome || \
~/gitrepos/seqhax/build/bin/seqhax grepbed -p $REGEX $genome \
> ${output}-tmp/$PATTERN-digest.txt

sed -i "s/$/\t"$PATTERN"\t"$STRAND"/" ${output}-tmp/${PATTERN}-digest.txt

python3 ${scriptdir}/find_cut_sites.py \
$output-tmp/${PATTERN}-digest.txt \
$genome_size > ${output}-tmp/${PATTERN}-cuts.txt
