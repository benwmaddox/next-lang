fn main() {
    print("+12_345".parse_int().unwrap())
    print("-0".parse_int().unwrap())
    print("-2147483648".parse_int().unwrap())
    print("2147483647".parse_int().unwrap())
    print("-9223372036854775808".parse_long().unwrap())
    print("9223372036854775807".parse_long().unwrap())

    print("-100".parse_int_radix(2).unwrap())
    print("+17".parse_int_radix(8).unwrap())
    print("1_234".parse_int_radix(10).unwrap())
    print("ff".parse_int_radix(16).unwrap())
    print("-10000000000000000000000000000000".parse_int_radix(2).unwrap())
    print("1111111111111111111111111111111".parse_int_radix(2).unwrap())
    print("-20000000000".parse_int_radix(8).unwrap())
    print("17777777777".parse_int_radix(8).unwrap())
    print("-100".parse_long_radix(2).unwrap())
    print("+17".parse_long_radix(8).unwrap())
    print("1_234".parse_long_radix(10).unwrap())
    print("-ff".parse_long_radix(16).unwrap())
    print("-1000000000000000000000000000000000000000000000000000000000000000".parse_long_radix(2).unwrap())
    print("111111111111111111111111111111111111111111111111111111111111111".parse_long_radix(2).unwrap())
    print("-1000000000000000000000".parse_long_radix(8).unwrap())
    print("777777777777777777777".parse_long_radix(8).unwrap())
    print("-80000000".parse_int_radix(16).unwrap())
    print("7fffffff".parse_int_radix(16).unwrap())
    print("-8000000000000000".parse_long_radix(16).unwrap())
    print("7fffffffffffffff".parse_long_radix(16).unwrap())

    print("0xff".parse_int_literal().unwrap())
    print("0XFF".parse_int_literal().unwrap())
    print("0B10_01".parse_int_literal().unwrap())
    print("1_000".parse_int_literal().unwrap())
    print("0x80000000".parse_int_literal().unwrap())
    print("0xffffffff".parse_int_literal().unwrap())

    let ascii: Ascii max 16 = "pre-12_345-post"
    let text: Text max 8 bytes max 8 = "x+77y"
    let raw: Bytes max 8 = b"abc-9def"
    print(ascii.slice(3..10).parse_int().unwrap())
    print(text.slice(1..4).parse_int().unwrap())
    print(raw.slice(3..5).parse_int().unwrap())
}
