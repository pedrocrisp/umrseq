# BED File Chromosome Recombination Tool

This script recombines split chromosomes in a BED file back into full chromosomes.

## Prerequisites

**Python Requirements:**
```bash
pip install pandas
```

That's it! Unlike the bigWig version, this script doesn't require any external tools.

## Usage

```bash
python recombine_bed.py <input.bed> <conversion_table.csv> <output.bed> [--no-sort]
```

### Arguments

- `input.bed` - Input BED file with split chromosomes
- `conversion_table.csv` - CSV file with chromosome conversion information
- `output.bed` - Output BED file with combined chromosomes
- `--no-sort` - Optional flag to skip sorting (faster but output won't be sorted)

### Examples

**Basic usage (with sorting):**
```bash
python recombine_bed.py \
    input_split.bed \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    output_combined.bed
```

**Skip sorting for speed:**
```bash
python recombine_bed.py \
    input_split.bed \
    Morex_pseudomolecules_v2_splits_chr1_7_Un_Pt_to_chr_corrected_N.csv \
    output_combined.bed \
    --no-sort
```

## What the script does

1. **Loads conversion table** - Reads your CSV with chromosome mappings
2. **Transforms coordinates** - Applies offsets to recombine split chromosomes:
   - `chr1H0` + `chr1H1` → `chr1H`
   - `chr2H0` + `chr2H1` → `chr2H`
   - etc.
3. **Sorts BED file** - Organizes by chromosome and position (unless --no-sort is used)
4. **Preserves all columns** - Keeps all BED fields (name, score, strand, etc.)

## BED File Support

The script works with:
- **BED3** (chrom, start, end)
- **BED6** (chrom, start, end, name, score, strand)
- **BED12** (full format)
- **Custom BED** (any number of additional columns)

All columns after the first three (chrom, start, end) are preserved exactly as-is.

## Conversion Table Format

Your CSV should have these columns:
- `seqname_part`: Split chromosome name (e.g., chr1H0, chr1H1)
- `seqname`: Combined chromosome name (e.g., chr1H)
- `start_convert_to_part`: Offset to add to coordinates

## Example Transformation

**Input BED (split chromosomes):**
```
chr1H0    100    200    feature1    100    +
chr1H1    100    200    feature2    100    +
chr2H0    500    600    feature3    100    -
```

**Output BED (combined chromosomes):**
```
chr1H    100         200         feature1    100    +
chr1H    262169429   262169529   feature2    100    +
chr2H    500         600         feature3    100    -
```

Note: chr1H1 coordinates have 262,169,329 added to them based on the conversion table.

## Performance

- **Small files** (<1M lines): Completes in seconds
- **Large files** (>10M lines): May take a few minutes, especially with sorting
- Use `--no-sort` to speed up processing if sorting isn't needed

## Notes

- Header lines (starting with #, track, or browser) are preserved
- Empty lines are preserved
- Malformed lines are skipped with a warning
- Progress is shown every 100,000 lines
- The script automatically handles both Unix and Windows line endings
