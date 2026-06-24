#!/usr/bin/env bash
#
# flagstat_summary.sh
# Run samtools flagstat per sample (one pass per BAM) and summarize:
#   - total alignments (all records, incl. secondary/supplementary)
#   - secondary alignments (0 = none present)
#   - properly paired count and percentage
# Also saves each sample's full flagstat to <sample>.flagstat.txt for the record.
#
# Usage:
#   ./flagstat_summary.sh samples.txt [bam_dir] [out_dir] > flagstat_summary.tsv
#
set -uo pipefail

SAMPLE_LIST="${1:-samples.txt}"   # text file: one sample name per line
BAM_DIR="${2:-.}"                 # directory containing *_sorted.bam files
OUT_DIR="${3:-flagstat}"          # where to save per-sample flagstat reports
THREADS=12                        # threads for samtools

mkdir -p "$OUT_DIR"

printf "sample\ttotal_alignments\tsecondary\tproperly_paired\tproperly_paired_pct\n"

while IFS= read -r sample || [[ -n "$sample" ]]; do
    sample="$(echo "$sample" | tr -d '[:space:]')"
    [[ -z "$sample" ]] && continue

    bam="${BAM_DIR}/${sample}_sorted.bam"
    if [[ ! -f "$bam" ]]; then
        echo "WARNING: missing file, skipping: $bam" >&2
        continue
    fi

    # one pass over the BAM; keep the full report and parse the fields we need
    fs="$(samtools flagstat -@ "$THREADS" "$bam")"
    echo "$fs" > "${OUT_DIR}/${sample}.flagstat.txt"

    # field 1 of each relevant line = QC-passed count
    total=$(echo "$fs"     | awk 'NR==1{print $1; exit}')
    secondary=$(echo "$fs" | awk '/secondary/{print $1; exit}')
    proppair=$(echo "$fs"  | awk '/properly paired/{print $1; exit}')
    # the "(NN.NN%" token on the properly-paired line -> strip parens/percent
    proppct=$(echo "$fs"   | awk '/properly paired/{
                                    for(i=1;i<=NF;i++) if($i ~ /%/){
                                        gsub(/[()%]/,"",$i); print $i; exit }
                                  }')

    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$sample" "$total" "$secondary" "$proppair" "${proppct:-NA}"

done < "$SAMPLE_LIST"

# -----------------------------------------------------------------------------
# Quick reads of the output:
#   secondary == 0 for every row        -> no read has a secondary alignment
#   properly_paired_pct == 100.00       -> all pairs flagged proper (rare in practice)
#
# If you'd rather parse robustly, flagstat can emit JSON:
#   samtools flagstat -@ 12 -O json "$bam" | jq '."QC-passed reads"'
# (requires jq).
# -----------------------------------------------------------------------------