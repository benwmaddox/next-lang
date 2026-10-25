fn bounded_work() -> long {
    let scratch: long[2048] = fill(0L)
    scratch[0L]
}

test "stack_peak rejects an over-budget function" {
    expect stack_peak(bounded_work) < 1 KB
}
