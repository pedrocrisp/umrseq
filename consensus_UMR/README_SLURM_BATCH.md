# SLURM Batch Processing for Chromosome Recombination

This package contains SLURM array job scripts for parallel processing of bigWig and BED files with split chromosomes.

## Files Included

### BigWig Processing
- `recombine_bigwig_sbatch.sh` - Submission wrapper
- `recombine_bigwig.sh` - Job script (runs for each sample)
- `recombine_bigwig.py` - Python script that does the actual work

### BED Processing
- `recombine_bed_sbatch.sh` - Submission wrapper
- `recombine_bed.sh` - Job script (runs for each sample)
- `recombine_bed.py` - Python script that does the actual work

## Setup

### 1. Place all scripts in the same directory

```bash
# Your working directory structure should look like:
.
├── recombine_bigwig_sbatch.sh
├── recombine_bigwig.sh
├── recombine_bigwig.py
├── recombine_bed_sbatch.sh
├── recombine_bed.sh
├── recombine_bed.py
├── samples.txt
├── Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv
└── bigwigs/
    ├── barley_GP_embryo_MAPQ10.bw
    ├── barley_GP_callus_MAPQ10.bw
    └── ...
```

### 2. Make scripts executable

```bash
chmod +x recombine_bigwig_sbatch.sh recombine_bigwig.sh
chmod +x recombine_bed_sbatch.sh recombine_bed.sh
```

### 3. Create your sample list file

```bash
# samples.txt - one sample prefix per line (no file extensions)
cat > samples.txt << EOF
barley_GP_embryo
barley_GP_callus
barley_Morex_leaf
barley_RGT-Planet_callus
barley_RGT-Planet_leaf
EOF
```

## Usage

### Processing BigWig Files

```bash
bash recombine_bigwig_sbatch.sh \
    samples.txt \
    _MAPQ10.bw \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    ./bigwigs \
    ./bigwigs_combined \
    12:00:00 \
    8 \
    your_department
```

**Arguments:**
1. `samples.txt` - Sample prefixes (one per line)
2. `_MAPQ10.bw` - File suffix
3. `conversion_table.csv` - Chromosome conversion table
4. `./bigwigs` - Input directory
5. `./bigwigs_combined` - Output directory
6. `12:00:00` - Walltime (HH:MM:SS)
7. `8` - Memory in GB
8. `your_department` - SLURM account

### Processing BED Files

```bash
bash recombine_bed_sbatch.sh \
    samples.txt \
    _peaks.bed \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    ./beds \
    ./beds_combined \
    4:00:00 \
    4 \
    your_department
```

**Arguments:**
Same as bigWig but typically:
- Less memory needed (4 GB usually sufficient)
- Shorter walltime (4 hours usually sufficient)

## How It Works

### Array Job Submission

The `_sbatch.sh` scripts:
1. Read your sample list
2. Submit a SLURM array job with one task per sample
3. Each task processes one sample in parallel
4. Pass all necessary variables to the job script

### Individual Job Execution

The `.sh` scripts:
1. Load required modules
2. Get the sample name from the array index
3. Construct input/output filenames
4. Run the Python recombination script
5. Verify output was created successfully

## Monitoring Jobs

```bash
# Check job status
squeue -u $USER

# Check specific job
squeue -j <job_id>

# Check logs (they appear in logs/ directory)
ls logs/
tail logs/20250109-123456_recombine_bigwig/recombine_bigwig_o_12345_1
```

## Log Files

All logs are saved in timestamped directories:

```
logs/
└── 20250109-123456_recombine_bigwig/
    ├── script.log                    # Copy of job script
    ├── sbatch_runner.log             # Copy of submission script
    ├── conversion_table.csv          # Copy of conversion table
    ├── recombine_bigwig_o_12345_1    # stdout for array task 1
    ├── recombine_bigwig_e_12345_1    # stderr for array task 1
    ├── recombine_bigwig_o_12345_2    # stdout for array task 2
    └── ...
```

## Module Configuration

### Adjusting Module Names

Edit the module load commands in the `.sh` scripts to match your cluster:

**For bigWig processing:**
```bash
# In recombine_bigwig.sh, adjust these lines:
module load python/3.9
module load ucsc-tools
```

**For BED processing:**
```bash
# In recombine_bed.sh, adjust this line:
module load python/3.9
```

### If modules aren't available

You can use conda environments instead:

```bash
# Create environment
conda create -n genomics python=3.9 pandas
conda install -c bioconda ucsc-bigwigtobedgraph ucsc-bedgraphtobigwig

# Then in your .sh scripts, replace module loads with:
source activate genomics
```

## Resource Guidelines

### BigWig Files
- **Memory:** 8-16 GB per job
- **Time:** 8-12 hours for large files
- **Disk space:** Output files similar size to input

### BED Files
- **Memory:** 2-4 GB per job
- **Time:** 1-4 hours for most files
- **Disk space:** Output files similar size to input

## Troubleshooting

### "Input file not found"
- Check that file suffix matches exactly
- Verify input directory path
- Ensure sample names in samples.txt don't include the suffix

### "bigWigToBedGraph not found"
- Install UCSC tools or adjust module names
- See README.md or README_BED.md for installation instructions

### Jobs fail immediately
- Check module names are correct for your cluster
- Verify Python has pandas installed
- Check that all Python scripts are in the working directory

### "Permission denied"
- Make scripts executable: `chmod +x *.sh`

## Example Complete Workflow

```bash
# 1. Set up files
ls
# Should show: scripts, samples.txt, conversion_table.csv, bigwigs/

# 2. Submit jobs
bash recombine_bigwig_sbatch.sh \
    samples.txt \
    _MAPQ10.bw \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    bigwigs \
    bigwigs_combined \
    12:00:00 \
    8 \
    my_department

# 3. Monitor progress
squeue -u $USER
watch -n 60 'squeue -u $USER'  # Auto-refresh every 60 seconds

# 4. Check results
ls bigwigs_combined/
# Should show: barley_GP_embryo_MAPQ10.bw, etc.

# 5. Check logs
tail logs/*/recombine_bigwig_o_*_1
```

## Notes

- The scripts create output directories automatically
- Intermediate files are cleaned up after successful completion
- Chromosome sizes files are kept for reference
- All logs are preserved in timestamped directories
- Jobs can be requeued automatically if they fail due to node issues
