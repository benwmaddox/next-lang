test "reservation has room for the computed bound" {
    let scratch: long[1024] = fill(7L)
    expect scratch[1023L] == 7L
}
