#!/usr/bin/env Rscript

##################################################
## CPM-normalise a UMR x sample read count matrix (edgeR), and write a
## second table filtered to UMRs with CPM >= 0.1 in at least 2 samples.
##
## Usage: Rscript 24-UMR_combine_calls_cpm.R <input.tsv> <output_cpm.tsv> <output_cpm_flt.tsv>
##################################################

args <- commandArgs(trailingOnly = TRUE)
input_tsv <- args[1]
output_cpm_tsv <- args[2]
output_flt_tsv <- args[3]

library("edgeR")
library("tibble")

dfr <- read.csv(input_tsv, sep = "\t", header = TRUE, row.names = 1)
df <- as.data.frame(cpm(dfr))

df2 <- round(df, 3)
df3 <- tibble::rownames_to_column(df2, "UMR_ID")
write.table(df3, file = output_cpm_tsv, sep = "\t", quote = FALSE, row.names = FALSE)

# keep UMRs with CPM >= 0.1 in at least 2 samples
df.f1 <- rowMeans(df)
df.f2 <- apply(df, 1, function(x) sum(x >= 0.1))
df$f1 <- df.f1
df$f2 <- df.f2
df.f <- subset(df, f2 >= 2)
df.f$f1 <- NULL
df.f$f2 <- NULL

df.f3 <- tibble::rownames_to_column(round(df.f, 3), "UMR_ID")
write.table(df.f3, file = output_flt_tsv, sep = "\t", quote = FALSE, row.names = FALSE)
