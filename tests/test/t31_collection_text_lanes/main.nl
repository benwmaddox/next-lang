struct Record {
    ascii: Ascii max 160
    text: Text max 100 bytes max 400
    bytes: Bytes max 256
    id: int
}

struct LargePage {
    contents: Ascii max 65
}

struct StaticRow {
    note: Text max 100 bytes max 400
}

global STATIC_ROWS: StaticRow[2] = fill(StaticRow { note: "hello" })

fn make_static_map() -> map<int, StaticRow, 2> {
    var values: map<int, StaticRow, 2> = map {}
    values.set(7, StaticRow { note: "world" }).unwrap()
    values
}

const STATIC_MAP: map<int, StaticRow, 2> = make_static_map()

fn make_static_texts() -> list<Text max 100 bytes max 400, 2> {
    var values: list<Text max 100 bytes max 400, 2> = list {}
    values.push("first").unwrap()
    values
}

const STATIC_TEXTS: list<Text max 100 bytes max 400, 2> = make_static_texts()

fn long_text() -> Text max 100 bytes max 400 {
    "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" +
    "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" + "😀" +
    "😀" + "😀" + "😀" + "😀" + "😀"
}

test "global collection constants initialize large text slots" {
    expect STATIC_ROWS[0L].note == "hello"
    expect STATIC_ROWS[1L].note == "hello"
    STATIC_ROWS[0L].note = "updated"
    expect STATIC_ROWS[0L].note == "updated"
    expect STATIC_ROWS[1L].note == "hello"
    expect STATIC_MAP.get(7).unwrap().note == "world"
    var texts: list<Text max 100 bytes max 400, 2> = STATIC_TEXTS
    expect texts.count() == 1L
    expect texts.push("second").is_ok()
    expect texts[0L] == "first"
    expect texts[1L] == "second"
    expect STATIC_TEXTS.count() == 1L
}

test "copied collections own independent text and byte slots" {
    let long_ascii: Ascii max 160 =
        "0123456789" + "0123456789" + "0123456789" + "0123456789" + "0123456789" +
        "0123456789" + "0123456789" + "0123456789" + "0123456789" + "0123456789"
    let long_bytes: Bytes max 256 =
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789"
    var original: list<Record, 2> = list {}
    expect original.push(Record {
        ascii: long_ascii,
        text: long_text(),
        bytes: long_bytes,
        id: 1,
    }).is_ok()
    var copied = original

    original[0L].ascii = "original"
    original[0L].text = "original text"
    original[0L].bytes = b"original bytes"
    expect copied[0L].ascii == long_ascii
    expect copied[0L].text == long_text()
    expect copied[0L].bytes == long_bytes

    copied[0L].ascii = "copy"
    copied[0L].text = "copy text"
    copied[0L].bytes = b"copy bytes"
    expect original[0L].ascii == "original"
    expect original[0L].text == "original text"
    expect original[0L].bytes == b"original bytes"
    expect copied[0L].ascii == "copy"
    expect copied[0L].text == "copy text"
    expect copied[0L].bytes == b"copy bytes"
}

test "a dirtied large slot can be reused for a short collection value" {
    let dirty: Ascii max 65 =
        "0123456789" + "0123456789" + "0123456789" + "0123456789" +
        "0123456789" + "0123456789" + "12345"
    expect dirty.len() == 65L

    var pages: list<LargePage, 1024> = list {}
    for index in 0..1024 { expect pages.push(LargePage { contents: dirty }).is_ok() }
    expect pages[1023L].contents == dirty
    for index in 0..1024 { expect pages.pop().is_some() }
    expect pages.push(LargePage { contents: "fresh" }).is_ok()
    expect pages[0L].contents == "fresh"
}

fn main() {}
