fn append_growing(buffer: grow Bytes max 12, piece: Bytes max 8) -> Result<(), Full> {
    buffer.try_append(piece)
}

fn utf8_offset(value: Bytes max 8) -> long {
    match value.validate_utf8() {
        ok(_) => -1L,
        err(error) => error.valid_up_to
    }
}

fn text_offset(value: Bytes max 8) -> long {
    match value.to_text() {
        ok(_) => -1L,
        err(error) => error.valid_up_to
    }
}

test "Bytes count, checked indexing, and proven pushes" {
    var value: Bytes max 4 = b"ab"
    expect value.count() == 2L
    expect value[0L] == 97
    expect value[1L] == 98
    value.push(99)
    value.push(100)
    expect value.count() == 4L
    expect value[2L] == 99
    expect value[3L] == 100
}

test "Bytes push proofs account for bounded loop growth" {
    var value: Bytes max 3 = Bytes.empty()
    for index in 0..3 { value.push(97) }
    expect value == b"aaa"
    expect value.push(98).is_err()
}

test "Bytes append accepts a slice of its own live contents" {
    var value: Bytes max 8 = b"abcd"
    let empty_bytes: Bytes max 8 = Bytes.empty()
    expect value.try_append(empty_bytes).is_ok()
    expect value.try_append(value.slice(1L..3L)).is_ok()
    expect value == b"abcdbc"
    expect value.count() == 6L
}

test "Bytes append and push report Full without changing live contents" {
    var value: Bytes max 3 = b"abc"
    expect value.try_append(b"d").is_err()
    expect value.push(100).is_err()
    discard value.push(100)
    expect value == b"abc"
    expect value.count() == 3L
}

test "Bytes grow parameters retain the builder contents" {
    var value: Bytes max 12 = b"start"
    append_growing(value, b"-end").unwrap()
    expect value == b"start-end"
}

test "UTF-8 validation reports Rust valid_up_to offsets" {
    let overlong: Bytes max 4 = b"\xc0\xaf"
    let surrogate: Bytes max 4 = b"\xed\xa0\x80"
    let above_unicode: Bytes max 4 = b"\xf4\x90\x80\x80"
    let truncated: Bytes max 4 = b"ok\xe2\x82"
    let continuation: Bytes max 1 = b"\x80"
    expect utf8_offset(overlong) == 0L
    expect utf8_offset(surrogate) == 0L
    expect utf8_offset(above_unicode) == 0L
    expect utf8_offset(continuation) == 0L
    expect utf8_offset(truncated) == 2L
    expect text_offset(truncated) == 2L
    expect b"hello".validate_utf8().is_ok()
    expect b"hello".to_text().unwrap() == "hello"
}

fn main() {}
