# Crisp_codes
Scripts that I have made for the Crisp Lab. These scripts are generally used for in silico digests of any given genome by running the in-silico-digest_qsub.sh in an HPC environment.

2025-03-13 this is a copy of Misha's original in-silico-digest scripts copied over to the main UMR-seq project directory for ease of access, check with Misha which repo is now being updated, this was current as at 2025-03-13.

From Judy:
-Need to make a motifs.fa file with a fasta heading and the recognition sites
-Run the in silico sbatch followed by process fragments sbatch
-The blacklist file we want is the *fragments-filtered-50%Ns.bed file generated after process fragments

In barley, for reference when running with various species:
-In silico needs lots of memory and process fragments needs lots of walltime
-100gb of mem and 3 hrs walltime

Run in-silico-digest_sbatch.sh:
-This bash script calls on other scripts
-Calls process-motifs.sh first
-Process-motifs.sh calls on convert_bases.py
-Process-motifs.sh makes numerous files: motifs.txt, motifs-regex.txt, digest-template.txt, and fragment-template.txt

Install seqhax:
module load miniconda3/23.9.0-0
source $EBROOTMINICONDA3/etc/profile.d/conda.sh
conda create --name seqhax python=3.8
conda activate seqhax
conda install -c bioconda seqhax=0.8.6
conda deactivate
