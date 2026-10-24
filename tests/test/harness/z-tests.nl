test "a from later file" {
    expect true
}

test "runtime overflow is isolated" {
    let too_big = 2147483647 + 1
    print(too_big)
}

test "later test still runs" {
    print(66)
    expect true
}
