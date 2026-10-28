fn read_text(value: Text max 4 bytes max 16) -> long {
    print(value)
    print(value.len())
    print(value.byte_len())
    value.len()
}

fn forward_text(value: Text max 4 bytes max 16) {
    print(read_text(value))
}

fn main() {
    let source: Ascii max 4 = "cat"
    print(read_text(source))
    forward_text(source)

    let text: Text max 2 bytes max 8 = "é😀"
    print(read_text(text))
    forward_text(text)
}
