fn main() {
    var values: list<long, 8192> = list {}
    for index: long in 0L..8192L {
        discard values.push(index + 1L)
    }

    var reserve: list<long, 30000> = list {}
    print(reserve.count())

    var checksum = 0L
    for round: long in 0L..2048L {
        var pass = 0L
        for index: long in 0L..8192L {
            pass += values[index]
            values[index] += 1L
        }
        checksum += pass
    }

    print(checksum)
    print(values[0L])
    print(values[8191L])
}
