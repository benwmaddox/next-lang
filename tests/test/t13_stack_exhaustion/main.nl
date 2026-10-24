test "bounded local fits the normal stack reservation" {
    let values: long[8192] = fill(1L)
    expect values[8191L] == 1L
}

test "iteration region is released each time" {
    for i: long in 0L..8L {
        let scratch: long[1024] = fill(i)
        expect scratch[0L] == i
    }
}
