from __future__ import print_function
import os
from math import *
import sys


ENZYMES = {
    "CNNR": "MspJI",
    "YNNG": "MspJI",
    "CC": "FspEI",
    "GG": "FspEI",
    "N": "Extra"
}
ENZYME_MODS = {
    "MspJI": [4,9],
    "FspEI": [4,12],
    "McrBC": [0,0],
    "Extra": [0,0]
}

def main():
    file           = sys.argv[1]
    chrom_len_file = sys.argv[2]
    uniq_frags     = find_cuts(file, chrom_len_file)

    eprint("Printing digestion results.")
    print_to_file(uniq_frags)
    eprint("Digestion done")

def print_to_file(array):
    uniq_arr = list(set(array))
    #uniq_arr.sort(key = lambda tup: (tup[0],tup[1]))
    i = 0
    while i < len(uniq_arr):
        chrom  = uniq_arr[i][0]
        start  = uniq_arr[i][1]

        print(chrom
            + "\t"
            + str(start))
        i += 1

def find_cuts(file, chrom_len_file):
    frag_starts  = []
    chr_length   = create_length_dict(chrom_len_file)

    eprint("Finding cut sites.")
    with open(file) as f:
        for count, line in enumerate(f):
            # Variables
            chrom   = line.split()[0]
            initial = line.split()[1]
            pattern = line.split()[3]
            strand  = line.split()[4]
            cutter  = Enzyme(pattern,strand)
            final   = int(initial) + int(cutter.offset)

            if final < 1:
                final = 1
            elif final > chr_length[chrom]:
                final = chr_length[chrom]

            frag_starts.append((chrom,final))
            #eprint("Cut " + str(count) + " found")

    for chr in chr_length.keys():
        frag_starts.append((chr,1))
        frag_starts.append((chr,chr_length[chr]))

    eprint("Cut sites found.")
    return frag_starts

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def create_length_dict(file):

    chr_length = {}

    with open(file) as l:
        for line in l:
            chr_length[line.split()[0]] = int(line.split()[1])
    return chr_length


class Enzyme:


    def __init__(self,pattern,strand):
        self.pattern  = pattern
        self.strand   = strand
        self.p_length = len(pattern)
        self.enzyme   = ENZYMES[self.pattern]
        self.overhang = ENZYME_MODS[self.enzyme][0]
        self.min_n    = ENZYME_MODS[self.enzyme][1]

        if self.enzyme == "Extra":
            self.p_length = 0

        self.offset   = self.determine_offset(
            self.enzyme,
            self.overhang,
            self.min_n,
            self.p_length,
            self.strand
            )

    def determine_offset(self,enzyme,overhang,min_n,p_length,strand):
        offset = p_length + min_n + floor(overhang / 2)
        if strand == "-":
            offset = -offset + p_length
        return offset

if __name__ == "__main__":
    main()
