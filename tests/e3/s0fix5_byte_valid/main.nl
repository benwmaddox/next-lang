fn main() {
    var raw: Bytes max 2 = Bytes.empty()
    discard raw.push(0)
    discard raw.push(255)
    print(raw[0L])
    print(raw[1L])
}
