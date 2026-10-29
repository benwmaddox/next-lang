struct Pair {
    snapshot: Ascii max 3,
    output: Ascii max 4,
}

fn append_snapshot(snapshot: Ascii max 3, output: grow Ascii max 4) {
    discard output.try_append("!")
    discard output.try_append(snapshot)
    print(snapshot)
    print(output)
}

fn publish_then_fail(output: grow Ascii max 8) -> Result<(), Full> {
    discard output.try_append("p")
    err(Full)
}

fn main() {
    var ascii: Ascii max 3 = "ab"
    print(ascii.try_append("cd"))
    print(ascii)
    print(ascii.len())

    var text: Text max 2 bytes max 5 = "é"
    print(text.try_append("😀"))
    print(text)
    print(text.len())
    print(text.byte_len())

    var raw: Bytes max 3 = b"AB"
    print(raw.try_append(b"CD"))
    print(raw.len())
    print(raw[0L])
    print(raw[1L])
    print(raw.push(67))
    print(raw.push(68))
    print(raw.len())
    print(raw[2L])

    var full_ascii: Ascii max 2 = "ab"
    print(full_ascii.try_append("c"))
    print(full_ascii)

    var full_text: Text max 1 bytes max 8 = "😀"
    print(full_text.try_append("é"))
    print(full_text.len())
    print(full_text.byte_len())

    var empty_ascii: Ascii max 0 = ""
    print(empty_ascii.try_append("x"))
    print(empty_ascii.len())

    var empty_text: Text max 0 bytes max 0 = ""
    print(empty_text.try_append("é"))
    print(empty_text.len())
    print(empty_text.byte_len())

    var empty_bytes: Bytes max 0 = Bytes.empty()
    print(empty_bytes.try_append(b"x"))
    print(empty_bytes.push(1))
    print(empty_bytes.len())

    var self_append: Ascii max 8 = "ab"
    print(self_append.try_append(self_append))
    print(self_append)

    var overlapping: Ascii max 8 = "abcd"
    print(overlapping.try_append(overlapping.slice(1L..3L)))
    print(overlapping)

    var pair = Pair { snapshot: "ab", output: "" }
    append_snapshot(pair.snapshot, pair.output)
    print(pair.snapshot)
    print(pair.output)

    var published: Ascii max 8 = "a"
    print(publish_then_fail(published))
    print(published)
}
