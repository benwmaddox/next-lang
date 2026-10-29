fn main() {
    var text: Text max 2 bytes max 8 = ""
    let bytes: Bytes max 1 = b"x"
    discard text.try_append(bytes)
}
