// E3c formatting helpers. These write only into caller-provided destinations;
// their callers prove the destination capacity from the formatted value's
// maximum and the padding width.

fn nl_text_format_digit_count(value: long, radix: long) -> long {
    var remaining = value
    if remaining > 0L { remaining = 0L - remaining }
    var digits = 1L
    remaining = remaining / radix
    for step in 0L..64L {
        if remaining == 0L { break }
        digits += 1L
        remaining = remaining / radix
    }
    digits
}

fn nl_text_format_number(value: long, radix: long, destination: sys.Addr) -> long {
    var remaining = value
    if remaining > 0L { remaining = 0L - remaining }
    let digits = nl_text_format_digit_count(value, radix)
    let sign = if value < 0L { 1L } else { 0L }
    if sign != 0L { sys.store8(destination, 0L, 45) }
    var place = sign + digits - 1L
    for step in 0L..digits {
        let digit = 0L - (remaining % radix)
        let code = if digit < 10L { 48L + digit } else { 87L + digit }
        sys.store8(destination, place, (int)code)
        remaining = remaining / radix
        place -= 1L
    }
    sign + digits
}

fn nl_text_format_ascii_upper(source: sys.Addr, byte_length: long, destination: sys.Addr) -> long {
    for index in 0L..byte_length {
        let value = sys.load8(source, index)
        let upper = if value >= 97 && value <= 122 { value - 32 } else { value }
        sys.store8(destination, index, upper)
    }
    byte_length
}

fn nl_text_format_pad_zero(value: long, target_width: long, destination: sys.Addr) -> long {
    var remaining = value
    if remaining > 0L { remaining = 0L - remaining }
    let digits = nl_text_format_digit_count(value, 10L)
    let sign = if value < 0L { 1L } else { 0L }
    let length = sign + digits
    let zeros = if target_width > length { target_width - length } else { 0L }
    if sign != 0L { sys.store8(destination, 0L, 45) }
    for step in 0L..zeros {
        sys.store8(destination, sign + step, 48)
    }
    var place = sign + zeros + digits - 1L
    for step in 0L..digits {
        let digit = 0L - (remaining % 10L)
        sys.store8(destination, place, (int)(48L + digit))
        remaining = remaining / 10L
        place -= 1L
    }
    length + zeros
}

fn nl_text_format_pad(
    source: sys.Addr,
    byte_length: long,
    codepoints: long,
    target_width: long,
    pad_left: bool,
    destination: sys.Addr,
) -> long {
    let padding = if target_width > codepoints { target_width - codepoints } else { 0L }
    let source_offset = if pad_left { padding } else { 0L }
    let pad_offset = if pad_left { 0L } else { byte_length }
    for index in 0L..padding {
        sys.store8(destination, pad_offset + index, 32)
    }
    for index in 0L..byte_length {
        sys.store8(destination, source_offset + index, sys.load8(source, index))
    }
    byte_length + padding
}
