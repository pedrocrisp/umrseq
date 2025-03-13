import sys

def test(genome_size,cut_file):
    for chrom in chrom_names(genome_size):
        arr = set()
        print(chrom)
        for site in cut_array(cut_file):
            if site[0] == chrom:
                arr.add(site)
                #print(site)
                print(len(arr))

def cut_array(cut_file):
    file = open(cut_file)
    for line in file:
        yield (line.split()[0],int(line.split()[1]))

def main():
    cut_file    = sys.argv[1]
    filters     = sys.argv[2]
    genome_size = sys.argv[3]
    output      = sys.argv[4]
    sizes       = create_length_dict(genome_size)
    
    with open(output + "-fragments.txt","w") as file:
        file.write("Chrom\tStart\tEnd\tLength\n")
    with open(output + "-fragments-filtered.txt","w") as file:
        file.write("Chrom\tStart\tEnd\tLength\n")

    for chrom in chrom_names(genome_size):
        calc_frags(cut_file, chrom, filters, sizes, output)

def create_length_dict(file):

    chr_length = {}

    with open(file) as l:
        for line in l:
            chr_length[line.split()[0]] = int(line.split()[1])
    return chr_length

def chrom_names(genome_size):
    file = open(genome_size)
    for line in file:
        yield line.split()[0]


def chrom_frags(cut_file, chrom):
    arr = cut_array(cut_file)
    for frag in arr:
        if frag[0] == chrom:
            yield frag

def calc_frags(cut_file, chrom, filters, lengths, output):
    print("Processing " + chrom + ".", file = sys.stderr)
    uniq_arr = list(chrom_frags(cut_file, chrom))

    print("Sort " + chrom + ".", file = sys.stderr)
    uniq_arr.sort()
    print(chrom + " sorted.", file = sys.stderr)
    print("Number of fragments in "
        + chrom
        + " is "
        + str(len(uniq_arr)),
        file = sys.stderr)

    original_stdout = sys.stdout
    sys.stdout      = open(output + "-fragments.txt","a")

    print("Finding fragments in " + chrom + ".", file = sys.stderr)
    find_frags(uniq_arr, lengths, 1)
    print("Fragments found in " + chrom + ".", file = sys.stderr)

    sys.stdout      = open(output + "-fragments-filtered.txt","a")
    print("Finding fragments in "
        + chrom
        + " with a size of at least "
        + filters
        + " base pairs.",
        file = sys.stderr)
    find_frags(uniq_arr, lengths, filters)

    sys.stdout = original_stdout

    print(chrom + " processed.", file = sys.stderr)


def find_frags(uniq_arr,lengths, filters):
    i = 0
    while i < len(uniq_arr) - 1:
        chrom  = uniq_arr[i][0]
        start  = uniq_arr[i][1]

        if uniq_arr[i + 1][1] == lengths[chrom]:
            end = lengths[chrom]
        else:
            end = uniq_arr[i + 1][1] - 1

        length = int(end) - int(start) + 1
        if start == lengths[chrom]:
            length = 0

        if length >= int(filters):
            print(
                chrom
                + "\t"
                + str(start)
                + "\t"
                + str(end)
                + "\t"
                + str(length)
                )
        i += 1
            
if __name__ == "__main__":
    main()
