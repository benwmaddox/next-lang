fn decimal_matches_reference(value: long) -> bool {
    str(value) == reference_decimal(value)
}

fn reference_decimal(value: long) -> Ascii max 21 {
    let negative = value < 0L
    var current = if value > 0L { -value } else { value }
    var reversed: Bytes max 20 = Bytes.empty()
    if current == 0L { reversed.push(48).unwrap() }
    for digit_step in 0L..19L {
        if current == 0L { break }
        let remainder = 0L - (current % 10L)
        let digit: byte = match remainder {
            0L => 48,
            1L => 49,
            2L => 50,
            3L => 51,
            4L => 52,
            5L => 53,
            6L => 54,
            7L => 55,
            8L => 56,
            _ => 57,
        }
        reversed.push(digit).unwrap()
        current /= 10L
    }
    var output: Bytes max 21 = Bytes.empty()
    if negative { output.push(45).unwrap() }
    for digit_index in 0L..reversed.count() {
        output.push(reversed[reversed.count() - digit_index - 1L]).unwrap()
    }
    output.to_ascii().unwrap()
}

test "decimal formatting covers signs, extrema, and every digit boundary" {
    expect decimal_matches_reference(0L)
    expect decimal_matches_reference(1L)
    expect decimal_matches_reference(-1L)
    expect decimal_matches_reference(-2147483648L)
    expect decimal_matches_reference(2147483647L)
    expect decimal_matches_reference(-9223372036854775808L)
    expect decimal_matches_reference(9223372036854775807L)
    var power = 1L
    for exponent in 0L..18L {
        expect decimal_matches_reference(power - 1L)
        expect decimal_matches_reference(power)
        expect decimal_matches_reference(power + 1L)
        expect decimal_matches_reference(0L - (power - 1L))
        expect decimal_matches_reference(0L - power)
        expect decimal_matches_reference(0L - (power + 1L))
        power *= 10L
    }
}

test "decimal formatting writes correctly into Ascii Text and Bytes builders" {
    var ascii: Ascii max 40 = "v="
    ascii += str(-2147483648)
    ascii += ","
    ascii.try_append(str(9223372036854775807L)).unwrap()
    expect ascii == "v=-2147483648,9223372036854775807"

    var text: Text max 24 bytes max 24 = "v="
    text.try_append(str(-9223372036854775808L)).unwrap()
    expect text == "v=-9223372036854775808"
    expect text.len() == 22L
    expect text.byte_len() == 22L

    var byte_value: Bytes max 24 = b"v="
    byte_value.try_append(str(2147483647).bytes()).unwrap()
    expect byte_value == b"v=2147483647"

    var too_small_ascii: Ascii max 2 = "x"
    expect too_small_ascii.try_append(str(-1L)).is_err()
    expect too_small_ascii == "x"
    var too_small_text: Text max 2 bytes max 2 = "x"
    expect too_small_text.try_append(str(-1L)).is_err()
    expect too_small_text == "x"
    var too_small_bytes: Bytes max 2 = b"x"
    expect too_small_bytes.try_append(str(-1L).bytes()).is_err()
    expect too_small_bytes == b"x"
}
