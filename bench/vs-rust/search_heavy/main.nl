fn less(ctx: long, a: long, b: long) -> bool {
    a < b
}

fn main() {
    var values: list<long, 10000> = list {}
    var seed = 1L

    for index: long in 0L..10000L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        discard values.push(seed)
    }

    var compare_ctx = 0L
    sort_by(values, compare_ctx, less)

    var checksum = 0L
    var seed2 = 42L
    for round: long in 0L..10000000L {
        seed2 = (seed2 * 1103515245L + 12345L) % 2147483648L
        let target = seed2 % 2147483648L
        let found = binary_search(values, target) ?? -1L
        checksum += found
    }

    print(checksum)
    print(values[0L])
    print(values[9999L])
}
