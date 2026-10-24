#!/usr/bin/env python3
"""
Script to recombine split chromosomes in a BED file.
Converts split chromosome coordinates back to full chromosome coordinates.
"""

import pandas as pd
import sys
import os

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

def transform_bed(input_bed, output_bed, conversion_dict):
    """Transform BED file coordinates using conversion table."""
    print(f"Transforming coordinates in {input_bed}...")
    
    converted_count = 0
    unchanged_count = 0
    header_lines = []
    
    with open(input_bed, 'r') as infile, open(output_bed, 'w') as outfile:
        for line_num, line in enumerate(infile, 1):
            # Handle header/track/browser lines
            if line.startswith('#') or line.startswith('track') or line.startswith('browser'):
                header_lines.append(line)
                outfile.write(line)
                continue
            
            # Skip empty lines
            if not line.strip():
                outfile.write(line)
                continue
            
            parts = line.strip().split('\t')
            
            # BED files must have at least 3 columns (chrom, start, end)
            if len(parts) < 3:
                print(f"Warning: Skipping malformed line {line_num} (less than 3 columns): {line.strip()}")
                continue
            
            try:
                chrom = parts[0]
                start = int(parts[1])
                end = int(parts[2])
                remaining_fields = parts[3:]  # Preserve all additional columns
                
                # Check if this chromosome needs conversion
                if chrom in conversion_dict:
                    new_chrom = conversion_dict[chrom]['seqname']
                    offset = conversion_dict[chrom]['offset']
                    new_start = start + offset
                    new_end = end + offset
                    
                    # Write transformed line
                    outfile.write(f"{new_chrom}\t{new_start}\t{new_end}")
                    if remaining_fields:
                        outfile.write('\t' + '\t'.join(remaining_fields))
                    outfile.write('\n')
                    converted_count += 1
                else:
                    # Chromosome not in conversion table - keep as-is
                    outfile.write(line)
                    unchanged_count += 1
                
                if line_num % 100000 == 0:
                    print(f"  Processed {line_num:,} lines...")
                    
            except ValueError as e:
                print(f"Warning: Skipping line {line_num} due to error: {e}")
                print(f"  Line content: {line.strip()}")
                continue
    
    print(f"\nTransformation complete:")
    print(f"  - Header lines: {len(header_lines)}")
    print(f"  - Converted: {converted_count:,} lines")
    print(f"  - Unchanged: {unchanged_count:,} lines")
    print(f"  - Total output: {converted_count + unchanged_count:,} data lines")

def sort_bed(input_bed, output_bed):
    """Sort BED file by chromosome and start position."""
    print(f"\nSorting BED file...")
    
    # Read file and separate headers from data
    headers = []
    data_lines = []
    
    with open(input_bed, 'r') as f:
        for line in f:
            if line.startswith('#') or line.startswith('track') or line.startswith('browser'):
                headers.append(line)
            elif line.strip():  # Skip empty lines
                data_lines.append(line.strip())
    
    # Parse and sort data lines
    parsed_lines = []
    for line in data_lines:
        parts = line.split('\t')
        if len(parts) >= 3:
            try:
                chrom = parts[0]
                start = int(parts[1])
                parsed_lines.append((chrom, start, line))
            except ValueError:
                print(f"Warning: Could not parse line for sorting: {line}")
                parsed_lines.append((parts[0], 0, line))  # Keep it but put at start
    
    # Sort by chromosome name, then by start position
    parsed_lines.sort(key=lambda x: (x[0], x[1]))
    
    # Write sorted output
    with open(output_bed, 'w') as f:
        # Write headers first
        for header in headers:
            f.write(header)
        
        # Write sorted data
        for _, _, line in parsed_lines:
            f.write(line + '\n')
    
    print(f"Sorted {len(parsed_lines):,} lines")
    print(f"Output written to: {output_bed}")

def main():
    if len(sys.argv) < 6 or len(sys.argv) > 7:
        print("Usage: python recombine_bed.py <input.bed> <conversion_table.csv> <output.bed> <sample_prefix> <output_dir> [--no-sort]")
        print("\nArguments:")
        print("  input.bed            Input BED file with split chromosomes")
        print("  conversion_table.csv CSV file with chromosome conversion information")
        print("  output.bed           Output BED file with combined chromosomes")
        print("  sample_prefix        Sample prefix for unique temp file names")
        print("  output_dir           Directory for intermediate files")
        print("  --no-sort            Optional: skip sorting step (output may be unsorted)")
        print("\nExample:")
        print("  python recombine_bed.py input_split.bed conversion_table.csv output_combined.bed sample1 ./output")
        sys.exit(1)

    input_bed = sys.argv[1]
    conversion_csv = sys.argv[2]
    output_bed = sys.argv[3]
    sample_prefix = sys.argv[4]
    output_dir = sys.argv[5]
    do_sort = True

    if len(sys.argv) == 7 and sys.argv[6] == '--no-sort':
        do_sort = False
        print("Note: Sorting disabled - output file may not be sorted")
    
    # Check input files exist
    if not os.path.exists(input_bed):
        print(f"ERROR: Input BED file not found: {input_bed}")
        sys.exit(1)
    if not os.path.exists(conversion_csv):
        print(f"ERROR: Conversion table not found: {conversion_csv}")
        sys.exit(1)
    
    # Intermediate file (use sample_prefix to avoid clashes when running in parallel)
    # Write to output_dir to keep working directory clean
    temp_bed = os.path.join(output_dir, f"{sample_prefix}_temp_transformed.bed")
    
    try:
        # Load conversion table
        conversion_dict = load_conversion_table(conversion_csv)
        
        if do_sort:
            # Transform to temporary file, then sort
            print("\n" + "="*60)
            print("Step 1: Transforming coordinates")
            print("="*60)
            transform_bed(input_bed, temp_bed, conversion_dict)
            
            print("\n" + "="*60)
            print("Step 2: Sorting BED file")
            print("="*60)
            sort_bed(temp_bed, output_bed)
            
            # Clean up temp file
            if os.path.exists(temp_bed):
                os.remove(temp_bed)
                print(f"\nCleaned up temporary file: {temp_bed}")
        else:
            # Transform directly to output file
            print("\n" + "="*60)
            print("Transforming coordinates (no sorting)")
            print("="*60)
            transform_bed(input_bed, output_bed, conversion_dict)
        
        print("\n" + "="*60)
        print("SUCCESS! Chromosome recombination complete.")
        print(f"Output file: {output_bed}")
        print("="*60)
        
    except Exception as e:
        print(f"\nERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
