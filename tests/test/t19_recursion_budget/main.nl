recursive fn descend(n: int) -> int {
    if n == 0 { 0 } else { descend(n - 1) + 1 }
}

test "recursive stack budget fails as a runtime failure" {
    let result = descend(100000000)
}
