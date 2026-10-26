fn start_bound() -> int {
    print(10)
    1
}

fn end_bound() -> int {
    print(20)
    3
}

fn nested_return() -> int {
    for outer in 0..4 {
        for inner in 0..4 {
            if inner == 2 { return outer * 10 + inner }
        }
    }
    99
}

fn unit_function() {}

fn main() {
    unit_function()
    let selected = if true { 4 } else if false { 5 } else { 6 }
    print(selected)
    {
        let scoped = 7
        print(scoped)
    }
    print(start_bound())
    for item in start_bound()..end_bound() {
        print(item)
    }
    for item in 2147483647..=2147483647 {
        print(item)
    }
    for item in 9223372036854775807L..=9223372036854775807L {
        print(item)
    }
    for outer in 1..=2 {
        for inner in 1..=4 {
            if inner == 2 { continue }
            if inner == 4 { break }
            print(outer * 10 + inner)
        }
    }
    print(nested_return())
}
