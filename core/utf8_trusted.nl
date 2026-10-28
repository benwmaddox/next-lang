// Trusted Text helpers. Call only after utf8_error_offset has accepted the bytes.
fn nl_text_codepoint_count_trusted(data: sys.Addr, byte_count: long) -> long {
    var points = 0L
    for offset in 0L..byte_count {
        if (sys.load8(data, offset) & 192) != 128 { points += 1L }
    }
    points
}
