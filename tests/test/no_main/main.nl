fn add_one(value: int) -> int {
    return value + 1
}

test "package can omit main" {
    expect add_one(2) == 3
}
