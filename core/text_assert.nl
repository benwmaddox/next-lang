// Fails on invalid UTF-8. Kept apart from the pure validator so the prelude can use that alone.
fn nl_text_assert_valid(data: sys.Addr, byte_count: long) {
    if utf8_error_offset(data, byte_count) != byte_count {
        nl_fail(22, 0, 0, 0)
    }
}
