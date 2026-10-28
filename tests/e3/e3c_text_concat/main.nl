fn clear_text(value: write Text max 3 bytes max 12) -> Text max 1 bytes max 4 {
    value = ""
    "!"
}

fn clear_text_and_return_zero(value: write Text max 3 bytes max 12) -> long {
    value = ""
    0L
}

fn main() {
    let left_ascii: Ascii max 4 = "ab"
    let right_ascii: Ascii max 4 = "cd"
    print(left_ascii + right_ascii)

    let left_text: Text max 1 bytes max 4 = "é"
    let right_text: Text max 1 bytes max 4 = "😀"
    let joined_text = left_text + right_text
    print(joined_text)
    print(joined_text.len())
    print(joined_text.byte_len())

    let left_bytes: Bytes max 2 = b"\xC3"
    let right_bytes: Bytes max 2 = b"\xA9"
    let joined_bytes = left_bytes + right_bytes
    print(joined_bytes[0L])
    print(joined_bytes[1L])
    print(joined_bytes.to_text().unwrap())

    var changing: Text max 3 bytes max 12 = "old"
    print(changing + clear_text(changing))
    print(changing)

    var slicing: Text max 3 bytes max 12 = "old"
    print(slicing.slice(clear_text_and_return_zero(slicing)..2L))
    print(slicing)
}
