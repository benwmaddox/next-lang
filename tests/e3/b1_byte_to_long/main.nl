fn widen(value: byte) -> long {
    value.to_long()
}

fn main() {
    let values: Bytes max 4 = b"\x00\x7F\x80\xFF"
    print(widen(values[0L]))
    print(widen(values[1L]))
    print(widen(values[2L]))
    print(widen(values[3L]))
}
