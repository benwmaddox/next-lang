struct Pair { value: int }

fn main() {
    print(1)
    print(2L)
    print(true)
}

test "bool expectation hook" {
    expect false
}

test "integer comparison expectation hook" {
    expect 1 == 2
}

test "long comparison expectation hook" {
    expect 1L == 2L
}

test "aggregate expectation hooks" {
    let left = Pair { value: 1 }
    let right = Pair { value: 2 }
    expect left == right
}

test "failure hook" {
    print(1 / 0)
}
