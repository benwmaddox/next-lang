fn three() -> int {
    return 3
}

fn left_value() -> int {
    print(1)
    return 7
}

fn right_value() -> int {
    print(2)
    return 7
}

fn skipped() -> bool {
    print(99)
    return false
}

fn main() {
    print(777)
}

test "z from alphabetically first file" {
    expect three() == 3
}

test "expect values and stop this test" {
    expect (three() == 4)
    print(999)
}

test "all comparisons and bool" {
    expect 2 == 2
    expect 2 != 3
    expect 2 < 3
    expect 2 <= 2
    expect 3 > 2
    expect 3 >= 3
    expect true
    var sum = 0
    for i in 0..2 { sum += i }
    {
        expect sum == 1
    }
    if true {
        expect sum == 1
    } else {
        expect false
    }
    var between = 0
    expect true
    between += 1
    expect between == 1
}

test "short circuit and operand order" {
    expect !(false && skipped())
    expect true || skipped()
    expect left_value() == right_value()
}

test "captured print and call" {
    print(55)
    expect three() == 3
}

test "bool comparison values" {
    expect true == false
}

test "plain bool failure" {
    expect false
}

test "multiline source is preserved" {
    expect (
        three()
        == 4
    )
}
