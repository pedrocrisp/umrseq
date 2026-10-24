#!/bin/bash
#set -xe
set -xeuo pipefail

usage="USAGE:
bash 40-SNP_call_sbatch.sh <sample_list.txt> <bam_suffix> <bam_dir> <reference_fasta> <regions_list.txt> <output_dir> <walltime> <memory> <account_department>

Example:
bash 40-SNP_call_sbatch.sh samples.txt _sorted_NoDup_ProPairs.bam analysis/trimmed_align_bowtie2_filtered genome.fa regions.txt ./snps_raw 24:00:00 20 AccountString

Arguments:
  sample_list.txt     - File containing sample name prefixes (one per line). These are also used as the
                         sample names in the VCF
  bam_suffix          - Suffix of each sample's BAM file (e.g., _sorted_NoDup_ProPairs.bam from
                         02b-filter-dups). Matched as '<sample_prefix>*<bam_suffix>'
  bam_dir             - Directory containing per-sample BAM files (each with a .bai or .csi index)
  reference_fasta     - Reference genome fasta used for the bowtie2 alignment (must have a .fai index)
  regions_list.txt    - One reference sequence name per line, one array task per line
                         (e.g. 'cut -f1 genome.fa.fai > regions.txt')
  output_dir          - Directory for per-region raw VCF files
  walltime            - Job walltime (HH:MM:SS format)
  memory              - Memory in GB per job
  account_department  - SLURM account/department name

This is step 1 of the UMR-seq SNP calling module: it calls SNPs jointly across
every sample in sample_list.txt, one array task per region in regions_list.txt.
Run it after 02b-filter-dups from the UMRseq pipeline."

#define step in the pipeline - should be the same name as the script
step=40-SNP_call

######### Setup ################
sample_list=$1
bam_suffix=$2
bam_dir=$3
reference_fasta=$4
regions_list=$5
output_dir=$6
walltime=$7
mem=$8
account_department=$9

if [ "$#" -lt "9" ]
then
echo "$usage"
exit -1
else
echo "Submitting regions listed in '$regions_list' for SNP calling"
echo "Sample list: '$sample_list'"
echo "BAM suffix: '$bam_suffix'"
echo "BAM directory: '$bam_dir'"
echo "Reference: '$reference_fasta'"
echo "Output directory: '$output_dir'"
echo ""
echo "Sample list:"
cat $sample_list
fi

#check inputs exist
for f in "$sample_list" "$regions_list" "$reference_fasta" "${reference_fasta}.fai"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: File not found: $f"
        exit -1
    fi
done
if [ ! -d "$bam_dir" ]; then
    echo "ERROR: BAM directory not found: $bam_dir"
    exit -1
fi

#make output dir if it doesnt exist yet
mkdir -p $output_dir

#build the BAM list and the matching sample names list (same order) once, here,
#so a missing BAM or index fails before any jobs are submitted
bam_list=${output_dir}/bam_list.txt
sample_names=${output_dir}/sample_names.txt
: > $bam_list
: > $sample_names

while IFS= read -r sample_prefix || [[ -n "$sample_prefix" ]]; do
    [[ -z "$sample_prefix" ]] && continue
    # BAM filenames may have extra text between the sample prefix and the suffix
    # so match by glob rather than exact concatenation
    bam_matches=("${bam_dir}/${sample_prefix}"*"${bam_suffix}")
    if [ ! -e "${bam_matches[0]}" ]; then
        echo "ERROR: No BAM file found matching ${bam_dir}/${sample_prefix}*${bam_suffix}"
        exit -1
    fi
    if [ "${#bam_matches[@]}" -ne 1 ]; then
        echo "ERROR: Expected exactly one BAM file matching ${bam_dir}/${sample_prefix}*${bam_suffix}, found ${#bam_matches[@]}:"
        printf '%s\n' "${bam_matches[@]}"
        exit -1
    fi
    bam_file="${bam_matches[0]}"
    if [ ! -f "${bam_file}.bai" ] && [ ! -f "${bam_file%.bam}.bai" ] && [ ! -f "${bam_file}.csi" ]; then
        echo "ERROR: No .bai or .csi index found for $bam_file"
        exit -1
    fi
    echo "$bam_file" >> $bam_list
    echo "$sample_prefix" >> $sample_names
done < "$sample_list"

echo "Number of samples: $(wc -l < $bam_list)"

#number of regions
# sbatch --array only takes a range; to handle 1 region, just use '1'
number_of_regions=`wc -l $regions_list | awk '{print $1}'`
if [[ "$number_of_regions" -eq 1 ]]
then
sbatch_t=1
else
sbatch_t="1-${number_of_regions}"
fi
echo "Number of regions: $number_of_regions"
echo "Argument to be passed to sbatch --array is '$sbatch_t'"

#find script to run, makes it file system agnostic
if
[[ $OSTYPE == darwin* ]]
then
readlink=$(which greadlink)
scriptdir="$(dirname $($readlink -f $0))"
else
scriptdir="$(dirname $(readlink -f $0))"
fi

########## Run #################

#make log folders
#make logs folder if it doesnt exist yet
mkdir -p logs

timestamp=$(date +%Y%m%d-%H%M%S)

#make logs folder, timestamped
log_folder=logs/${timestamp}_${step}
mkdir $log_folder

#script path and cat a record of what was run
script_to_sbatch=${scriptdir}/${step}.sh
cat $script_to_sbatch > ${log_folder}/script.log
cat $0 > ${log_folder}/sbatch_runner.log
cp $sample_list ${log_folder}/sample_list.txt
cp $regions_list ${log_folder}/regions_list.txt
cp $bam_list ${log_folder}/bam_list.txt

#submit sbatch and pass args
#-o and -e pass the file locations for std out/error
#--export additional variables to pass to the sbatch script including the array list and the dir structures
sbatch --array $sbatch_t \
-t ${walltime} \
-N 1 \
-n 1 \
--cpus-per-task 1 \
--mem ${mem}gb \
-o ${log_folder}/${step}_o_%A_%a \
-e ${log_folder}/${step}_e_%A_%a \
--export REGIONS_LIST=${regions_list},BAM_LIST=${bam_list},SAMPLE_NAMES=${sample_names},REFERENCE=${reference_fasta},OUTPUT_DIR=${output_dir} \
--account $account_department \
$script_to_sbatch

echo ""
echo "Jobs submitted! Monitor with: squeue --me"
echo "Check logs in: $log_folder"
