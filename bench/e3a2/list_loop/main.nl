fn main() {
    var values: list<long, 8> = [1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L]
    for repeat: long in 0L..200_000_000L {
        let salt = repeat % 251L + 1L
        for value in values { value = (value * 48271L + salt) % 2147483647L }
    }
    var checksum: long = 0L
    for value in values { checksum += value }
    print(checksum)
}
