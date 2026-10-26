struct Empty {}

struct Pair {
    value: int,
    enabled: bool,
    empty: Empty,
}

fn read_first(pair: Pair, ignored: int) -> int {
    pair.value
}

fn main() {
    let left = Pair { value: 7, enabled: true, empty: Empty {} }
    let same = left
    var other = left
    other.value = 8

    print(left)
    print(Empty {})
    print(left == same)
    print(left != other)
    var compare_snapshot = Pair { value: 7, enabled: true, empty: Empty {} }
    print(compare_snapshot == if true { compare_snapshot.value = 8; Pair { value: 7, enabled: true, empty: Empty {} } } else { Pair { value: 0, enabled: false, empty: Empty {} } })
    var call_snapshot = Pair { value: 5, enabled: false, empty: Empty {} }
    print(read_first(call_snapshot, if true { call_snapshot.value = 9; 0 } else { 0 }))
}
