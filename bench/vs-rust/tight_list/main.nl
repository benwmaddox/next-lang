fn main() {
    var values: list<long, 100000> = list {}
    var seed = 1L

    for index: long in 0L..100000L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        discard values.push(seed)
    }

    var checksum = 0L
    for round: long in 0L..10000L {
        for index: long in 0L..100000L {
            let v = values[index] + round
            if v % 2L == 0L {
                checksum += v
            } else {
                checksum -= v
            }
        }
    }

    print(checksum)
    print(values[0L])
    print(values[99999L])
}
