struct Card {
    heading: Ascii max 8
    caption: Text max 3 bytes max 12
    raw: Bytes max 4
}

enum Notice {
    Caption(Text max 3 bytes max 12),
    Binary(Bytes max 4),
    Label(Ascii max 8),
}

fn show_text(value: Text max 4) {
    print(value.len())
    print(value)
}

fn copy_text(value: Text max 4) -> Text max 4 { value }

fn maybe_caption() -> Option<Text max 3 bytes max 12> {
    some("é😀")
}

fn result_caption() -> Result<Text max 3 bytes max 12, TextError> {
    ok("雪")
}

fn main() {
    let empty_ascii: Ascii max 0 = Ascii.empty()
    let empty_text: Text max 0 bytes max 0 = Text.empty()
    let empty_bytes: Bytes max 0 = Bytes.empty()
    print(empty_ascii.len())
    print(empty_text.len())
    print(empty_text.byte_len())
    print(empty_bytes.len())
    print(empty_bytes.count())

    let short_ascii: Ascii max 4 = "ab"
    show_text(short_ascii)
    let returned_text = copy_text(short_ascii)
    print(returned_text)
    print(returned_text.len())
    print(returned_text.byte_len())

    let card = Card {
        heading: "hello",
        caption: "é😀",
        raw: b"\x00\xFF",
    }
    print(card.heading)
    print(card.caption)
    print(card.raw.len())
    print(card.raw[0L])
    print(card.raw[1L])

    match Notice.Caption(card.caption) {
        Caption(value) => print(value),
        Binary(value) => print(value.len()),
        Label(value) => print(value),
    }
    match Notice.Binary(card.raw) {
        Caption(value) => print(value),
        Binary(value) => print(value.len()),
        Label(value) => print(value),
    }
    match maybe_caption() {
        some(value) => print(value),
        none => print("missing"),
    }
    match result_caption() {
        ok(value) => print(value),
        err(_) => print("error"),
    }
}
