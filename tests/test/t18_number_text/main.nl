type SmallAbs = int 0..=5
type SmallMin = int 0..=5
type SmallMax = int 2..=7
type SmallClamp = int 1..=6

fn absolute_range(value: int -5..=3) -> SmallAbs { abs(value) }
fn minimum_range(left: int 0..=5, right: int 2..=7) -> SmallMin { min(left, right) }
fn maximum_range(left: int 0..=5, right: int 2..=7) -> SmallMax { max(left, right) }
fn clamp_range(value: int, low: int 1..=3, high: int 4..=6) -> SmallClamp {
    clamp(value, low, high)
}

test "decimal, hexadecimal, and binary formatting cover signed values" {
    expect str(0) == "0"
    expect str(-42) == "-42"
    expect str(-2147483648) == "-2147483648"
    expect str(-9223372036854775808L) == "-9223372036854775808"
    expect str(0).parse_int() == some(0)
    expect str(-2147483648).parse_int() == some(-2147483648)
    expect str(2147483647).parse_int() == some(2147483647)
    expect str(-9223372036854775808L).parse_long() == some(-9223372036854775808L)
    expect str(9223372036854775807L).parse_long() == some(9223372036854775807L)
    expect str_hex(0) == "0"
    expect str_hex(255) == "ff"
    expect str_hex(-255) == "-ff"
    expect str_hex(-9223372036854775808L) == "-8000000000000000"
    expect str_hex(-2147483648).parse_int_radix(16) == some(-2147483648)
    expect str_hex(2147483647).parse_int_radix(16) == some(2147483647)
    expect str_hex(-9223372036854775808L).parse_long_radix(16) == some(-9223372036854775808L)
    expect str_hex(9223372036854775807L).parse_long_radix(16) == some(9223372036854775807L)
    expect str_bin(0) == "0"
    expect str_bin(13) == "1101"
    expect str_bin(-5) == "-101"
    expect str_bin(-2147483648).parse_int_radix(2) == some(-2147483648)
    expect str_bin(2147483647).parse_int_radix(2) == some(2147483647)
    expect str_bin(-9223372036854775808L).parse_long_radix(2) == some(-9223372036854775808L)
    expect str_bin(9223372036854775807L).parse_long_radix(2) == some(9223372036854775807L)
}

test "padding handles width, side, zero sign, and mixed maxima" {
    let short: Ascii max 2 = "x"
    let wide: Ascii max 12 = "longer"
    let padded_short: Ascii max 4 = pad(short, 4)
    let unchanged_wide: Ascii max 12 = pad(wide, 3)
    expect pad(short, 4) == "   x"
    expect padded_short == "   x"
    expect pad("ab", 2) == "ab"
    expect pad("longer", 3) == "longer"
    expect unchanged_wide == "longer"
    expect pad_right("x", 4) == "x   "
    expect pad_zero(42, 5) == "00042"
    expect pad_zero(-42, 5) == "-0042"
    expect pad_zero(-12345, 3) == "-12345"
    expect pad_zero(7, 1) == "7"
    expect pad("é𝄞", 4) == "  é𝄞"
    let padded_text: Text max 4 bytes max 10 = pad("é𝄞", 4)
    expect padded_text.len() == 4L
    expect padded_text.byte_len() == 8L
    expect pad_right("é", 3) == "é  "
}

test "integer parsing round trips extremes and accepts separated digits" {
    expect "-2147483648".parse_int() == some(-2147483648)
    expect "2147483647".parse_int() == some(2147483647)
    expect "-9223372036854775808".parse_long() == some(-9223372036854775808L)
    expect "9223372036854775807".parse_long() == some(9223372036854775807L)
    expect "-0".parse_int() == some(0)
    expect "+1_234".parse_long() == some(1234L)
    expect "12_345".parse_int() == some(12345)
    expect "ff".parse_int_radix(16) == some(255)
    expect "-100".parse_int_radix(2) == some(-4)
    expect "+17".parse_int_radix(8) == some(15)
    expect "1_234".parse_int_radix(10) == some(1234)
    expect "-1000000000000000000000".parse_long_radix(8) == some(-9223372036854775808L)
    expect "777777777777777777777".parse_long_radix(8) == some(9223372036854775807L)
    expect "-9223372036854775808".parse_long_radix(10) == some(-9223372036854775808L)
    expect "0xff".parse_int_literal() == some(255L)
    expect "0B10_01".parse_int_literal() == some(9L)
    expect "1_000".parse_int_literal() == some(1000L)
}

test "integer parsing rejects malformed digits, prefixes, and overflow" {
    expect "".parse_int().is_none()
    expect "+".parse_long().is_none()
    expect "-".parse_int().is_none()
    expect " 12".parse_int().is_none()
    expect "12 ".parse_int().is_none()
    expect "1__0".parse_int().is_none()
    expect "_1".parse_int().is_none()
    expect "1_".parse_int().is_none()
    expect "0xff".parse_int_radix(16).is_none()
    expect "0b10".parse_int_radix(2).is_none()
    expect "12L".parse_int_literal().is_none()
    expect "0x_FF".parse_int_literal().is_none()
    expect "2147483648".parse_int().is_none()
    expect "-2147483649".parse_int().is_none()
    expect "9223372036854775808".parse_long().is_none()
    expect "-9223372036854775809".parse_long().is_none()
    expect "١".parse_int().is_none()
    expect b"12é".parse_int().is_none()
}

test "Ascii, Text, and Bytes slices parse through their original length units" {
    let ascii: Ascii max 16 = "pre-12_345-post"
    let text: Text max 8 = "x+77y"
    let bytes: Bytes max 8 = b"abc-9def"
    expect ascii.slice(3..10).parse_int() == some(-12345)
    expect text.slice(1..4).parse_int() == some(77)
    expect bytes.slice(3..5).parse_int() == some(-9)
}

test "ASCII byte helpers classify and change only ASCII letters" {
    let digit: byte = 48
    let upper: byte = 65
    let lower: byte = 122
    let tab: byte = 9
    let non_ascii: byte = 255
    expect digit.is_digit()
    expect !digit.is_alpha()
    expect upper.is_alpha()
    expect !upper.is_digit()
    expect tab.is_space()
    expect !digit.is_space()
    expect upper.to_lower() == 97
    expect lower.to_upper() == 90
    expect non_ascii.to_lower() == 255
    expect non_ascii.to_upper() == 255
}

test "abs, min, max, and clamp retain provable refinement ranges" {
    expect absolute_range(-5) == 5
    expect absolute_range(3) == 3
    expect minimum_range(4, 6) == 4
    expect maximum_range(4, 6) == 6
    expect clamp_range(-100, 2, 5) == 2
    expect clamp_range(100, 2, 5) == 5
    expect abs(-99L) == 99L
    expect min(5L, 7L) == 5L
    expect max(5L, 7L) == 7L
    expect clamp(100L, 1L, 20L) == 20L
}

fn main() {}
