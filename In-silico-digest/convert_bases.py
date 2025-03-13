import sys

IUPAC_CODES = str.maketrans({
    "A": "[Aa]",
    "C": "[Cc]",
    "G": "[Gg]",
    "T": "[Tt]",
    "R": "[AGag]",
    "Y": "[CTct]",
    "S": "[GCgc]",
    "W": "[ATat]",
    "K": "[GTgt]",
    "M": "[ACac]",
    "B": "[CGTcgt]",
    "D": "[AGTagt]",
    "H": "[ACTact]",
    "V": "[ACGacg]",
    "N": "[ACGTacgt]"
})

def main():
    pattern_file = sys.argv[1]
    with open(pattern_file) as file:
        for line in file:
            line2 = line.translate(IUPAC_CODES)
            print(line.split()[0] + "\t" + line2.rstrip())

if __name__ == "__main__":
    main()
