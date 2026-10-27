struct BenchCell { left: long, right: long }

fn main() {
    var values: BenchCell[8] = [
        BenchCell { left: 1L, right: 2L }, BenchCell { left: 1L, right: 2L },
        BenchCell { left: 1L, right: 2L }, BenchCell { left: 1L, right: 2L },
        BenchCell { left: 1L, right: 2L }, BenchCell { left: 1L, right: 2L },
        BenchCell { left: 1L, right: 2L }, BenchCell { left: 1L, right: 2L },
    ]
    for repeat: long in 0L..2_000_000_000L {
        let index = repeat % 8L
        let salt = repeat % 251L + 1L
        values[index].left = (values[index].left * 48271L + salt) % 2147483647L
        values[index].right = (values[index].right * 48271L + values[index].left) % 2147483647L
    }
    var checksum: long = 0L
    for value in values { checksum += value.left + value.right }
    print(checksum)
}
