fn bump(value: write long, salt: long) {
    value = (value * 48271L + salt % 251L + 1L) % 2147483647L
}

fn main() {
    var values: list<long, 8> = [0L, 0L, 0L, 0L, 0L, 0L, 0L, 0L]
    for repeat: long in 0L..2_000_000_000L {
        bump(values[repeat % 8L], repeat)
    }
    var checksum: long = 0L
    for value in values { checksum += value }
    print(checksum)
}
