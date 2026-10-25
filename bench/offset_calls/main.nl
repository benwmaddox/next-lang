fn bump(values: write list<long, 8192>, index: long) {
    var scratch: list<long, 30000> = list {}
    discard scratch.push(values[index])
    values[index] += 1L
}

fn copy_values(values: list<long, 8192>) -> list<long, 8192> {
    values
}

fn main() {
    var values: list<long, 8192> = list {}
    for index: long in 0L..8192L {
        discard values.push(index + 1L)
    }

    var checksum = 0L
    for index: long in 0L..1000L {
        bump(values, index % 8192L)
        let copied = copy_values(values)
        checksum += copied[index % 8192L]
    }

    print(checksum)
    print(values[0L])
    print(values[999L])
}
