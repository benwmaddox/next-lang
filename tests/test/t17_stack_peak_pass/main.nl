fn bounded_work() -> long {
    let scratch: long[128] = fill(0L)
    scratch[0L]
}

test "stack_peak accepts a generous budget" {
    expect stack_peak(bounded_work) < 2 MB
    expect bounded_work() == 0L
}
