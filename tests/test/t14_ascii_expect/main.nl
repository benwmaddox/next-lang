fn option_result() -> Option<Ascii max 4> { some("ab") }

test "Ascii comparison uses bytes including NUL" {
    expect "a\0b" == "a\0b"
    expect "a\0b" < "a\0c"
    expect ascii_upper("a\0b") == "A\0B"

    let narrow: Ascii max 10 = "a"
    let wide: Ascii max 20 = "a"
    let wider: Ascii max 30 = "b"
    expect narrow == wide
    expect narrow != wider
    expect narrow < wider
    expect narrow <= wide
    expect wider > narrow
    expect wide >= narrow
}

test "Ascii Option expectation uses the other operand's type" {
    let o = option_result()
    expect o == some("ab")
}
