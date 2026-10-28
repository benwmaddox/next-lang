fn text_from_int(value: int) -> Ascii max 11 { str(value) }
fn text_from_long(value: long) -> Ascii max 20 { str(value) }
fn text_from_byte(value: byte) -> Ascii max 3 { str(value) }

fn main() {
    let negative_one: Ascii max 2 = str(-1)
    print(negative_one)
    let sum: Ascii max 1 = str(1 + 2)
    print(sum)
    let single_digit: Ascii max 1 = str(7)
    print(single_digit)

    print(text_from_int(-2147483648))
    print(text_from_int(2147483647))
    print(text_from_long(-9223372036854775808L))
    print(text_from_long(9223372036854775807L))
    print(text_from_byte(255))

    print(str_hex(-9223372036854775808L))
    print(str_bin(-9223372036854775808L))
    print(pad("é😀", 4))
    print(pad_right("é", 3))
    print(pad_zero(-42, 5))
    print(pad_zero(-9223372036854775808L, 20))
}
