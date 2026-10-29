fn main() {
    var bytes: Bytes max 4 = Bytes.empty()
    let ascii: Ascii max 1 = "x"
    discard bytes.try_append(ascii)
}
