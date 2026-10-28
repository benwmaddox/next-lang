fn main() {
    let text: Text max 4 bytes max 10 = "Aé😀Z"
    print(text.len())
    print(text.byte_len())
    print(text.slice(1L..3L))
    print(text.slice(2L..3L))
    print(text.slice(0L..1L))
    print(text.slice(4L..4L).len())

    let ascii: Ascii max 8 = "word"
    print(ascii.slice(1L..3L))
    print(ascii.slice(1L..4L).len())
}
