fn print_ascii_bytes(value: Ascii max 16) {
    for index in 0L..value.len() {
        print(value.bytes()[index])
    }
}

fn main() {
    let small: Ascii max 8 = "cat"
    let same_width: Ascii max 20 = "cat"
    let later: Ascii max 12 = "dog"
    let short_text: Text max 8 bytes max 24 = "cat"
    let long_text: Text max 8 bytes max 24 = "café"
    let first_bytes: Bytes max 4 = b"\x00\xFF"
    let same_bytes: Bytes max 8 = b"\x00\xFF"
    let later_bytes: Bytes max 4 = b"\x01\x00"

    print(small == same_width)
    print(small != later)
    print(small < later)
    print(small <= same_width)
    print(later > small)
    print(later >= same_width)

    print(short_text == "cat")
    print(short_text != long_text)
    print(short_text < long_text)
    print(short_text <= "cat")
    print(long_text > short_text)
    print(long_text >= "café")

    print(first_bytes == same_bytes)
    print(first_bytes != later_bytes)
    print(first_bytes < later_bytes)
    print(first_bytes <= same_bytes)
    print(later_bytes > first_bytes)
    print(later_bytes >= same_bytes)

    print(small == short_text)
    print(small != long_text)
    print(small < long_text)
    print(small <= short_text)
    print(long_text > small)
    print(long_text >= short_text)

    print_ascii_bytes(ascii_upper("\0@AZ[`az{\x7F"))
}
