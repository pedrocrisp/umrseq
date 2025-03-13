args <- commandArgs(TRUE)
frag.table <- args[1]
frag.output <- args[2]
threshold <- as.numeric(args[3])

frags <- read.table(frag.table, sep = "\t", header = T)
frags$PercentN <- sapply(1:length(frags$Length),
                         function (x) frags[x,3] * 100 / frags[x,2])

filtered.frags <- frags[which(frags$PercentN <= threshold),]
write.table(filtered.frags, file = frag.output, sep = "\t", quote = F, row.names = F)
