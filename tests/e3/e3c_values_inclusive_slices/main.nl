fn main() {
    let text: Text max 4 bytes max 10 = "Aé😀Z"
    print(text.slice(1L..=2L))
    print(text.slice(3L..=3L))
    let ascii: Ascii max 8 = "word"
    print(ascii.slice(0L..=0L))
}
