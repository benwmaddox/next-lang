fn main() {
    let all_invalid =
        "".parse_int().is_none() &&
        "+".parse_long().is_none() &&
        "-".parse_int().is_none() &&
        " 12".parse_int().is_none() &&
        "12 ".parse_int().is_none() &&
        "1__0".parse_int().is_none() &&
        "_1".parse_int().is_none() &&
        "1_".parse_int().is_none() &&
        "++1".parse_long().is_none() &&
        "-+1".parse_long().is_none() &&
        "0xff".parse_int_radix(16).is_none() &&
        "0b10".parse_int_radix(2).is_none() &&
        "-1".parse_int_literal().is_none() &&
        "12L".parse_int_literal().is_none() &&
        "0x_FF".parse_int_literal().is_none() &&
        "0o77".parse_int_literal().is_none() &&
        "2147483648".parse_int().is_none() &&
        "-2147483649".parse_int().is_none() &&
        "9223372036854775808".parse_long().is_none() &&
        "-9223372036854775809".parse_long().is_none() &&
        "2147483648".parse_int_radix(10).is_none() &&
        "-80000001".parse_int_radix(16).is_none() &&
        "80000000".parse_int_radix(16).is_none() &&
        "ffffffff".parse_int_radix(16).is_none() &&
        "8000000000000000".parse_long_radix(16).is_none() &&
        "-8000000000000001".parse_long_radix(16).is_none() &&
        "9223372036854775808".parse_int_literal().is_none() &&
        "0x8000000000000000".parse_int_literal().is_none() &&
        "0xffffffffffffffff".parse_int_literal().is_none() &&
        "١".parse_int().is_none() &&
        b"12é".parse_int().is_none()
    print(all_invalid)
}
