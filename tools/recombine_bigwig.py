#!/usr/bin/env python3
"""
Script to recombine split chromosomes in a bigWig file.
Converts split chromosome coordinates back to full chromosome coordinates.
"""

import pandas as pd
import subprocess
import sys
import os

def convert_bigwig_to_bedgraph(bigwig_file, bedgraph_file):
    """Convert bigWig to bedGraph format."""
    print(f"Converting {bigwig_file} to bedGraph...")
    cmd = ['bigWigToBedGraph', bigwig_file, bedgraph_file]
    try:
        subprocess.run(cmd, check=True)
        print(f"Successfully created {bedgraph_file}")
    except FileNotFoundError:
        print("ERROR: bigWigToBedGraph not found. Please install UCSC tools.")
        print("Download from: http://hgdownload.soe.ucsc.edu/admin/exe/")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to convert bigWig to bedGraph: {e}")
        sys.exit(1)

def load_conversion_table(csv_file):
    """Load and return the chromosome conversion table."""
    print(f"Loading conversion table from {csv_file}...")
    df = pd.read_csv(csv_file)
    # Create a dictionary for easy lookup: seqname_part -> (seqname, offset)
    conversion_dict = {}
    for _, row in df.iterrows():
        conversion_dict[row['seqname_part']] = {
            'seqname': row['seqname'],
            'offset': row['start_convert_to_part']
        }
    print(f"Loaded {len(conversion_dict)} chromosome mappings")
    return conversion_dict

def transform_bedgraph(input_bedgraph, output_bedgraph, conversion_dict):
    """Transform bedGraph coordinates using conversion table."""
    print(f"Transforming coordinates in {input_bedgraph}...")
    
    converted_count = 0
    unchanged_count = 0
    
    with open(input_bedgraph, 'r') as infile, open(output_bedgraph, 'w') as outfile:
        for line_num, line in enumerate(infile, 1):
            if line.startswith('#') or line.startswith('track') or line.startswith('browser'):
                # Keep header lines as-is
                outfile.write(line)
                continue
            
            parts = line.strip().split('\t')
            if len(parts) < 4:
                print(f"Warning: Skipping malformed line {line_num}: {line.strip()}")
                continue
            
            chrom, start, end, value = parts[0], int(parts[1]), int(parts[2]), parts[3]
            
            # Check if this chromosome needs conversion
            if chrom in conversion_dict:
                new_chrom = conversion_dict[chrom]['seqname']
                offset = conversion_dict[chrom]['offset']
                new_start = start + offset
                new_end = end + offset
                outfile.write(f"{new_chrom}\t{new_start}\t{new_end}\t{value}\n")
                converted_count += 1
            else:
                # Chromosome not in conversion table - keep as-is
                outfile.write(line)
                unchanged_count += 1
            
            if line_num % 1000000 == 0:
                print(f"  Processed {line_num:,} lines...")
    
    print(f"Transformation complete:")
    print(f"  - Converted: {converted_count:,} lines")
    print(f"  - Unchanged: {unchanged_count:,} lines")

def sort_bedgraph(bedgraph_file, sorted_bedgraph):
    """Sort bedGraph file (required for bigWig conversion)."""
    print(f"Sorting {bedgraph_file}...")
    cmd = ['sort', '-k1,1', '-k2,2n', bedgraph_file]
    # Use LC_COLLATE=C for case-sensitive sorting (required for bedGraphToBigWig)
    env = os.environ.copy()
    env['LC_COLLATE'] = 'C'
    with open(sorted_bedgraph, 'w') as outfile:
        subprocess.run(cmd, stdout=outfile, check=True, env=env)
    print(f"Created sorted file: {sorted_bedgraph}")

def create_chrom_sizes(conversion_table_df, output_file):
    """Create chromosome sizes file from conversion table."""
    print(f"Creating chromosome sizes file: {output_file}...")
    
    # Get the maximum end position for each chromosome
    chrom_sizes = conversion_table_df.groupby('seqname')['end'].max().sort_index()
    
    with open(output_file, 'w') as f:
        for chrom, size in chrom_sizes.items():
            f.write(f"{chrom}\t{size}\n")
    
    print(f"Chromosome sizes written to {output_file}")
    print("Chromosomes and sizes:")
    for chrom, size in chrom_sizes.items():
        print(f"  {chrom}: {size:,} bp")

def convert_bedgraph_to_bigwig(bedgraph_file, chrom_sizes_file, bigwig_file):
    """Convert bedGraph to bigWig format."""
    print(f"Converting {bedgraph_file} to bigWig...")
    cmd = ['bedGraphToBigWig', bedgraph_file, chrom_sizes_file, bigwig_file]
    try:
        subprocess.run(cmd, check=True)
        print(f"Successfully created {bigwig_file}")
    except FileNotFoundError:
        print("ERROR: bedGraphToBigWig not found. Please install UCSC tools.")
        print("Download from: http://hgdownload.soe.ucsc.edu/admin/exe/")
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to convert bedGraph to bigWig: {e}")
        sys.exit(1)

def main():
    if len(sys.argv) != 6:
        print("Usage: python recombine_bigwig.py <input.bw> <conversion_table.csv> <output.bw> <sample_prefix> <output_dir>")
        print("\nExample:")
        print("  python recombine_bigwig.py input_split.bw conversion_table.csv output_combined.bw sample1 ./output")
        sys.exit(1)

    input_bigwig = sys.argv[1]
    conversion_csv = sys.argv[2]
    output_bigwig = sys.argv[3]
    sample_prefix = sys.argv[4]
    output_dir = sys.argv[5]
    
    # Check input files exist
    if not os.path.exists(input_bigwig):
        print(f"ERROR: Input bigWig file not found: {input_bigwig}")
        sys.exit(1)
    if not os.path.exists(conversion_csv):
        print(f"ERROR: Conversion table not found: {conversion_csv}")
        sys.exit(1)
    
    # Intermediate files (use sample_prefix to avoid clashes when running in parallel)
    # Write to output_dir to keep working directory clean
    temp_bedgraph = os.path.join(output_dir, f"{sample_prefix}_temp_input.bedGraph")
    transformed_bedgraph = os.path.join(output_dir, f"{sample_prefix}_temp_transformed.bedGraph")
    sorted_bedgraph = os.path.join(output_dir, f"{sample_prefix}_temp_sorted.bedGraph")
    chrom_sizes_file = os.path.join(output_dir, f"{sample_prefix}_chrom_sizes.txt")
    
    try:
        # Step 1: Convert bigWig to bedGraph
        convert_bigwig_to_bedgraph(input_bigwig, temp_bedgraph)
        
        # Step 2: Load conversion table
        conversion_dict = load_conversion_table(conversion_csv)
        conversion_df = pd.read_csv(conversion_csv)
        
        # Step 3: Transform coordinates
        transform_bedgraph(temp_bedgraph, transformed_bedgraph, conversion_dict)
        
        # Step 4: Sort the bedGraph
        sort_bedgraph(transformed_bedgraph, sorted_bedgraph)
        
        # Step 5: Create chromosome sizes file
        create_chrom_sizes(conversion_df, chrom_sizes_file)
        
        # Step 6: Convert back to bigWig
        convert_bedgraph_to_bigwig(sorted_bedgraph, chrom_sizes_file, output_bigwig)
        
        print("\n" + "="*60)
        print("SUCCESS! Chromosome recombination complete.")
        print(f"Output file: {output_bigwig}")
        print("="*60)
        
        # Clean up intermediate files
        print("\nCleaning up intermediate files...")
        for temp_file in [temp_bedgraph, transformed_bedgraph, sorted_bedgraph]:
            if os.path.exists(temp_file):
                os.remove(temp_file)
                print(f"  Removed {temp_file}")
        
        print(f"\nNote: Keeping {chrom_sizes_file} for reference")
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
