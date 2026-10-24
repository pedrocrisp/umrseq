# BigWig Chromosome Recombination Tool

This script recombines split chromosomes in a bigWig file back into full chromosomes.

## Prerequisites

You need the UCSC Genome Browser utilities installed:
- `bigWigToBedGraph`
- `bedGraphToBigWig`

### Installing UCSC Tools

**Linux:**
```bash
wget http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/bigWigToBedGraph
wget http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/bedGraphToBigWig
chmod +x bigWigToBedGraph bedGraphToBigWig
sudo mv bigWigToBedGraph bedGraphToBigWig /usr/local/bin/
```

**macOS:**
```bash
wget http://hgdownload.soe.ucsc.edu/admin/exe/macOSX.x86_64/bigWigToBedGraph
wget http://hgdownload.soe.ucsc.edu/admin/exe/macOSX.x86_64/bedGraphToBigWig
chmod +x bigWigToBedGraph bedGraphToBigWig
sudo mv bigWigToBedGraph bedGraphToBigWig /usr/local/bin/
```

**Or via conda:**
```bash
conda install -c bioconda ucsc-bigwigtobedgraph ucsc-bedgraphtobigwig
```

### Python Requirements

```bash
pip install pandas
```

## Usage

```bash
python recombine_bigwig.py <input.bw> <conversion_table.csv> <output.bw>
```

### Example

```bash
python recombine_bigwig.py \
    input_split.bw \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    output_combined.bw
```

## What the script does

1. **Converts bigWig to bedGraph** - Extracts the data into text format
2. **Loads conversion table** - Reads your CSV with chromosome mappings
3. **Transforms coordinates** - Applies offsets to recombine split chromosomes:
   - `chr1H0` + `chr1H1` → `chr1H`
   - `chr2H0` + `chr2H1` → `chr2H`
   - etc.
4. **Sorts bedGraph** - Required for bigWig conversion
5. **Creates chromosome sizes file** - Automatically generated from your conversion table
6. **Converts back to bigWig** - Creates the final combined file

## Conversion Table Format

Your CSV should have these columns:
- `seqname_part`: Split chromosome name (e.g., chr1H0, chr1H1)
- `seqname`: Combined chromosome name (e.g., chr1H)
- `start_convert_to_part`: Offset to add to coordinates
- `end`: Maximum position for each chromosome

## Output

- `output_combined.bw` - Your recombined bigWig file
- `chrom_sizes.txt` - Chromosome sizes file (kept for reference)

## Notes

- The script automatically cleans up intermediate bedGraph files
- Progress updates are printed during processing
- For large files, the sorting step may take some time
- The output bigWig will have chromosomes: chr1H-chr7H, chrUn, Mt, Pt
