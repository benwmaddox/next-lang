struct Holder {
    ascii: Ascii max 8,
    text: Text max 3 bytes max 12,
    bytes: Bytes max 4,
    sibling: int,
}

fn append_ascii(out: grow Ascii max 8) {
    discard out.try_append("z")
}

fn append_text_leaf(out: grow Text max 3 bytes max 12) {
    discard out.try_append("猫")
}

fn append_text_forward(out: grow Text max 3 bytes max 12) {
    append_text_leaf(out)
}

fn append_bytes(out: grow Bytes max 4) {
    discard out.try_append(b"\xFF")
}

fn main() {
    var ascii: Ascii max 4 = "ab"
    ascii += "c"
    print(ascii)
    print(ascii.try_append("d"))
    print(ascii)

    var exact: Ascii max 3 = "ab"
    exact += "c"
    print(exact)

    var holder = Holder {
        ascii: "x",
        text: "é",
        bytes: b"A",
        sibling: 42,
    }
    append_ascii(holder.ascii)
    append_text_forward(holder.text)
    append_bytes(holder.bytes)
    print(holder.ascii)
    print(holder.text)
    print(holder.text.len())
    print(holder.text.byte_len())
    print(holder.bytes.len())
    print(holder.bytes[0L])
    print(holder.bytes[1L])
    print(holder.sibling)

    var text: Text max 3 bytes max 8 = "é"
    print(text.try_append("a"))
    print(text)
    print(text.len())
    print(text.byte_len())

    var raw: Bytes max 4 = b"A"
    print(raw.push(255))
    print(raw.try_append(b"BC"))
    print(raw.len())
    print(raw[0L])
    print(raw[3L])
}
