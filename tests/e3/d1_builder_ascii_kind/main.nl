fn main() {
    var ascii: Ascii max 4 = ""
    let text: Text max 1 bytes max 4 = "é"
    discard ascii.try_append(text)
}
