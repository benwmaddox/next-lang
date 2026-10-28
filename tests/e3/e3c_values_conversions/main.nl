fn bytes_ascii_kind(value: Bytes max 8) -> long {
    match value.to_ascii() {
        ok(_) => 0L,
        err(error) => match error {
            InvalidUtf8 => 1L,
            NonAscii => 2L,
        },
    }
}

fn text_ascii_kind(value: Text max 4 bytes max 8) -> long {
    match value.to_ascii() {
        ok(_) => 0L,
        err(error) => match error {
            InvalidUtf8 => 1L,
            NonAscii => 2L,
        },
    }
}

fn text_error_code(value: TextError) -> long {
    match value {
        InvalidUtf8 => 1L,
        NonAscii => 2L,
    }
}

fn utf8_offset(value: Bytes max 8) -> long {
    match value.validate_utf8() {
        ok(_) => -1L,
        err(error) => error.valid_up_to,
    }
}

fn text_conversion_offset(value: Bytes max 8) -> long {
    match value.to_text() {
        ok(_) => -1L,
        err(error) => error.valid_up_to,
    }
}

fn main() {
    let valid_ascii: Bytes max 8 = b"plain"
    let invalid_utf8: Bytes max 8 = b"ok\xE2\x82"
    let valid_non_ascii: Bytes max 8 = b"\xC3\xA9"
    let ascii_text: Text max 4 bytes max 8 = "text"
    let non_ascii_text: Text max 1 bytes max 4 = "é"

    print(bytes_ascii_kind(valid_ascii))
    print(bytes_ascii_kind(invalid_utf8))
    print(bytes_ascii_kind(valid_non_ascii))
    print(text_ascii_kind(ascii_text))
    print(text_ascii_kind(non_ascii_text))
    print(text_error_code(TextError.InvalidUtf8))
    print(utf8_offset(valid_ascii))
    print(utf8_offset(invalid_utf8))
    print(text_conversion_offset(invalid_utf8))
}
