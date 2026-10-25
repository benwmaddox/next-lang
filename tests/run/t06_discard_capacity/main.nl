struct Item { value: long }

fn text_piece() -> Result<Text max 1 bytes max 4, Full> {
    ok("é")
}

fn append_text_piece(out: grow Text max 2 bytes max 8) -> Result<(), Full> {
    discard out.try_append(text_piece()?)
    ok(())
}

fn main() {
    var ascii: Ascii max 2 = Ascii.empty()
    discard ascii.try_append("a")
    print(ascii.len())

    var text: Text max 2 bytes max 8 = Text.empty()
    append_text_piece(text).unwrap()
    discard text.try_append("b")
    discard text.try_append("c")
    print(text.len())
    print(text.byte_len())

    var byte_limited: Text max 4 bytes max 2 = Text.empty()
    discard byte_limited.try_append("é")
    discard byte_limited.try_append("a")
    print(byte_limited.byte_len())

    var bytes: Bytes max 2 = Bytes.empty()
    discard bytes.try_append(b"x")
    discard bytes.push(121)
    discard bytes.try_append(b"z")
    print(bytes.count())

    var values: list<long, 2> = list {}
    discard values.push(1L)
    discard values.insert(0L, 2L)
    print(values.count())

    var mapped: map<long, long, 1> = map {}
    discard mapped.set(1L, 2L)
    print(mapped.count())

    var members: set<long, 1> = set {}
    discard members.add(3L)
    print(members.count())

    var items: pool<Item, 1> = pool {}
    discard items.add(Item { value: 4L })
    print(items.count())
}
