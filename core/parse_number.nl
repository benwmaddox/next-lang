fn parse_number_digit(value: int) -> int {
    if value >= 48 && value <= 57 { value - 48 }
    else if value >= 65 && value <= 70 { value - 55 }
    else if value >= 97 && value <= 102 { value - 87 }
    else { -1 }
}

// Parse ASCII integer text and write Option<int> or Option<long> directly to
// the caller's already allocated sum-value destination. Option tags use i32
// at byte 0; int payloads begin at byte 4 and long payloads at byte 8.
fn parse_integer_option(
    data: sys.Addr,
    byte_count: long,
    initial_radix: long,
    literal_mode: bool,
    target_bits: long,
    output: sys.Addr,
) {
    if sys.is_null(output) { return }
    if byte_count <= 0L || sys.is_null(data) || (target_bits != 32L && target_bits != 64L) {
        sys.store32(output, 0L, 1)
        return
    }

    var radix = initial_radix
    var cursor = 0L
    var negative = false
    if literal_mode {
        radix = 10L
        if byte_count >= 2L && sys.load8(data, 0L) == 48 {
            let prefix = sys.load8(data, 1L)
            if prefix == 120 || prefix == 88 {
                radix = 16L
                cursor = 2L
            } else if prefix == 98 || prefix == 66 {
                radix = 2L
                cursor = 2L
            } else { () }
        } else { () }
    } else {
        let first_byte = sys.load8(data, 0L)
        if first_byte == 43 || first_byte == 45 {
            negative = first_byte == 45
            cursor = 1L
        } else { () }
    }

    if (radix != 2L && radix != 8L && radix != 10L && radix != 16L) || cursor >= byte_count {
        sys.store32(output, 0L, 1)
        return
    }

    var minimum = -9223372036854775807L - 1L
    var maximum = 9223372036854775807L
    if target_bits == 32L {
        minimum = -2147483648L
        maximum = 2147483647L
    } else { () }
    let limit = if negative { minimum } else { -maximum }
    let multiply_limit = limit / radix
    var value = 0L
    var saw_digit = false
    var previous_separator = false
    for offset in cursor..byte_count {
        let current_byte = sys.load8(data, offset)
        if current_byte == 95 {
            if !saw_digit || previous_separator || offset + 1L >= byte_count {
                sys.store32(output, 0L, 1)
                return
            }
            let next_digit = parse_number_digit(sys.load8(data, offset + 1L))
            if next_digit < 0 || next_digit.to_long() >= radix {
                sys.store32(output, 0L, 1)
                return
            }
            previous_separator = true
        } else {
            let digit_int = parse_number_digit(current_byte)
            if digit_int < 0 || digit_int.to_long() >= radix {
                sys.store32(output, 0L, 1)
                return
            }
            let digit = digit_int.to_long()
            if value < multiply_limit {
                sys.store32(output, 0L, 1)
                return
            }
            value *= radix
            if value < limit + digit {
                sys.store32(output, 0L, 1)
                return
            }
            value -= digit
            saw_digit = true
            previous_separator = false
        }
    }
    if !saw_digit || previous_separator {
        sys.store32(output, 0L, 1)
        return
    }

    let parsed = if negative { value } else { -value }
    if target_bits == 32L {
        sys.store32(output, 4L, (int)parsed)
    } else {
        sys.store64(output, 8L, parsed)
    }
    sys.store32(output, 0L, 0)
}
