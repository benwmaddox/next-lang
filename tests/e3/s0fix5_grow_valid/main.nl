struct Holder {
    text: Ascii max 4,
    sibling: int,
}

fn append_ascii(out: grow Ascii max 4) {
    discard out.try_append("b")
}

fn append_text(out: grow Text max 2 bytes max 8) {
    discard out.try_append("é")
}

fn append_bytes(out: grow Bytes max 2) {
    discard out.push(255)
}

fn call_indirect(callback: fn(grow Ascii max 4), out: grow Ascii max 4) {
    callback(out)
}

fn main() {
    var ascii: Ascii max 4 = "a"
    append_ascii(ascii)
    print(ascii)

    let callback: fn(grow Ascii max 4) = append_ascii
    call_indirect(callback, ascii)
    print(ascii)

    var holder = Holder { text: "a", sibling: 9 }
    append_ascii(holder.text)
    print(holder.text)
    print(holder.sibling)

    var text: Text max 2 bytes max 8 = "a"
    append_text(text)
    print(text)

    var raw: Bytes max 2 = Bytes.empty()
    append_bytes(raw)
    print(raw[0L])
}
