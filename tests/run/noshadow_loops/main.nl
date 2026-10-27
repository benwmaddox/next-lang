fn first_bound() -> int {
    print(8)
    return 2
}

fn second_bound() -> int {
    print(9)
    return 2
}

fn take_long(value: long) {
    print(value)
}

fn return_from_nested_loops() -> int {
    for i in 0..2 {
        for j in 0..2 {
            return i * 10 + j
        }
    }
    return -1
}

fn main() {
    for i in 0..3 { print(i) }
    for i in 2..=4 { print(i) }
    for i in 4..2 { print(99) }
    for i in 1..=1 { print(i) }
    for i in -2..=0 { print(i) }

    for i in 2147483647..=2147483647 {
        print(i)
        continue
    }
    for i in 2147483647..=2147483647 { print(i) }
    for i in 9223372036854775807L..=9223372036854775807L {
        print(i)
        continue
    }
    for i in 9223372036854775807L..=9223372036854775807L { print(i) }

    for i: long in 0..2 { print(i) }
    let end_long = 2L
    for i in 0..end_long { print(i) }
    for i in 0..2 { take_long(i) }

    for i in first_bound()..second_bound() { print(99) }
    var end = 3
    for i in 0..end {
        print(i)
        end = 0
    }

    for i in 0..3 {
        if i == 1 { continue }
        for j in 0..3 {
            if j == 1 { continue }
            if j == 2 { break }
            print(i * 10 + j)
        }
    }

    for i in 0..3 {
        var fresh = 0
        fresh += 1
        print(fresh)
    }
    for i in 0..2 {
        print(i)
        for inner in 1..=1 { print(inner) }
    }
    print(return_from_nested_loops())
}
