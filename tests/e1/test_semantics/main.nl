fn int_max() -> int { 2147483647 }
fn int_min() -> int { -2147483648 }
fn long_max() -> long { 9223372036854775807L }
fn long_min() -> long { -9223372036854775808L }
fn print_true() -> bool { print(999); true }
fn print_false() -> bool { print(998); false }

test "arithmetic boundaries and signs" {
    expect int_min() == -2147483648
    expect int_max() == 2147483647
    expect long_min() == -9223372036854775808L
    expect long_max() == 9223372036854775807L
    expect int_min() + 1 == -2147483647
    expect int_max() - 1 == 2147483646
    expect 46340 * 46340 == 2147395600
    expect 3037000499L * 3037000499L == 9223372030926249001L
    expect -7 / 3 == -2
    expect 7 / -3 == -2
    expect -7 % 3 == -1
    expect 7 % -3 == 1
    expect -7L / 3L == -2L
    expect 7L / -3L == -2L
    expect -7L % 3L == -1L
    expect 7L % -3L == 1L
    expect int_min() % -1 == 0
    expect long_min() % -1L == 0L
    expect -int_max() < 0
}

test "short circuit suppresses failure" {
    expect false && (1 / 0 == 0)
    expect true || (1 / 0 == 0)
    expect !(false && print_true())
    expect true || print_false()
}

test "comparison expectation failure" {
    expect 2 == 3
    print(997)
}

test "long comparison expectation failure" {
    expect 2L == 3L
}

test "bool comparison expectation failure" {
    expect true == false
}

test "bool expectation failure" {
    expect false
}

test "multiline expectation failure" {
    expect (
        true &&
        false
    )
}

test "int addition overflow" {
    print(int_max() + 1)
}

test "long addition overflow" {
    print(long_max() + 1L)
}

test "int subtraction overflow" {
    print(int_min() - 1)
}

test "long subtraction overflow" {
    print(long_min() - 1L)
}

test "int multiplication overflow" {
    print(50000 * 50000)
}

test "long multiplication overflow" {
    print(3037000500L * 3037000500L)
}

test "int negation overflow" {
    let value = int_min()
    print(-value)
}

test "long negation overflow" {
    let value = long_min()
    print(-value)
}

test "int division by zero" {
    print(1 / 0)
}

test "long remainder by zero" {
    print(1L % 0L)
}

test "int minimum division by minus one" {
    print(int_min() / -1)
}

test "long minimum division by minus one" {
    print(long_min() / -1L)
}
