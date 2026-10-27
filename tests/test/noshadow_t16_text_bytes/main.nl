test "text and bytes preserve their distinct length units" {
    let value: Text max 3 = "a😀ß"
    expect value.len() == 3L
    expect value.byte_len() == 7L
    expect value.slice(1..3) == "😀ß"
    expect value.upper() == "A😀SS"
    expect "x" + "ß" == "xß"
    expect b"a" + b"bc" == b"abc"
    expect b"abc".slice(1..3) == b"bc"
}

test "Text counts a four-byte character at its declared maximum" {
    let value: Text max 1 = "😀"
    expect value.len() == 1L
    expect value.byte_len() == 4L
    let budget: Text max 1 bytes max 4 = "😀"
    expect budget.len() == 1L
    expect budget.byte_len() == 4L
}

fn empty_text() -> Text max 4 bytes max 16 { Text.empty() }

fn empty_bytes() -> Bytes max 5 { Bytes.empty() }

test "Text.empty and Bytes.empty use destination maxima" {
    let text: Text max 2 bytes max 8 = Text.empty()
    let returned_text = empty_text()
    let byte_value: Bytes max 3 = Bytes.empty()
    let returned_bytes = empty_bytes()
    expect text.len() == 0L
    expect text.byte_len() == 0L
    expect returned_text.len() == 0L
    expect byte_value.len() == 0L
    expect returned_bytes.len() == 0L
}

test "checked text conversions distinguish invalid UTF-8 and non-ASCII" {
    expect b"hello".to_text().unwrap() == "hello"
    expect b"hello".to_ascii().unwrap() == "hello"
    expect "é".to_ascii().is_err()
    expect b"hello".to_ascii().unwrap() == "hello"
}

fn read_text(value: Text max 8) -> long { value.len() }

fn main() {}

struct Slot {
    short: Ascii max 60
    blob: Bytes max 200
    note: Text max 80 bytes max 300
    count: int
}

struct Record {
    short: Ascii max 60
    note: Text max 8 bytes max 32
    count: int
}

fn replace_record(records: write list<Record, 1>, raw: Bytes max 8) -> Result<(), Utf8Error> {
    records[0L] = Record { short: "changed", note: raw.to_text()?, count: 99 }
    ok(())
}

test "bounded collection fields keep mixed size-class slots stable" {
    let wide_bytes: Bytes max 140 =
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789"
    let wide_text: Text max 40 bytes max 160 =
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀"
    var values: list<Slot, 2> = list {}
    expect values.push(Slot { short: "a", blob: b"small", note: "first", count: 1 }).is_ok()
    expect values.push(Slot { short: "b", blob: b"small", note: "second", count: 2 }).is_ok()
    values[0L].short = "inline replacement"
    values[0L].blob = wide_bytes
    values[0L].note = wide_text
    values[0L].note = "tiny"
    expect values[0L].short == "inline replacement"
    expect values[0L].blob.len() == 140L
    expect values[0L].note == "tiny"
    expect values[1L].short == "b"
    expect values[1L].blob == b"small"
    expect values[1L].note == "second"
}

test "same-class string replacement works at full capacity" {
    let hundred: Text max 100 bytes max 400 =
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀"
    let another: Text max 100 bytes max 400 =
        "😁😁😁😁😁😁😁😁😁😁" + "😁😁😁😁😁😁😁😁😁😁" +
        "😁😁😁😁😁😁😁😁😁😁" + "😁😁😁😁😁😁😁😁😁😁" +
        "😁😁😁😁😁😁😁😁😁😁" + "😁😁😁😁😁😁😁😁😁😁" +
        "😁😁😁😁😁😁😁😁😁😁" + "😁😁😁😁😁😁😁😁😁😁" +
        "😁😁😁😁😁😁😁😁😁😁" + "😁😁😁😁😁😁😁😁😁😁"
    var values: list<Text max 100 bytes max 400, 2> = list {}
    expect values.push(hundred).is_ok()
    expect values.push(hundred).is_ok()
    values[0L] = another
    expect values[0L] == another
    expect values[1L] == hundred
}

test "removed text and byte slots are immediately reusable" {
    var values: list<Slot, 1> = list {}
    for index in 0..8 {
        expect values.push(Slot { short: "x", blob: b"a value beyond inline", note: "a longer note", count: index }).is_ok()
        expect values.pop().is_some()
    }
    expect values.count() == 0L
}

test "a later failed text field leaves every earlier field unchanged" (env: Env) {
    let fs = env.fs
    var invalid_path: Path = list {}
    discard invalid_path.push(255)
    expect fs.write("invalid", invalid_path).is_ok()
    var invalid: Bytes max 8 = b""
    expect fs.read("invalid", invalid).is_ok()

    var records: list<Record, 1> = list {}
    expect records.push(Record { short: "original", note: "kept", count: 7 }).is_ok()
    let result = replace_record(records, invalid)
    expect result.is_err()
    expect records[0L].short == "original"
    expect records[0L].note == "kept"
    expect records[0L].count == 7
}

test "Ascii reads as Text through a descriptor without copying bytes" {
    let ascii: Ascii max 5 = "plain"
    expect read_text(ascii) == 5L
}

test "file and output capabilities accept Text and Bytes" (env: Env) {
    let fs = env.fs
    var data: Bytes max 16 = b""
    var text: Text max 4 bytes max 12 = ""
    match fs.write("bytes", b"raw") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.read("bytes", data) {
        ok(_) => {
            expect data.len() == 3L
            expect data.to_text().unwrap() == "raw"
            expect data == b"raw"
        },
        _ => { expect false }
    }
    match fs.write("text", "😀é") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.read("text", text) {
        ok(_) => {
            expect text.len() == 2L
            expect text.byte_len() == 6L
        },
        _ => { expect false }
    }
    expect fs.write("roundtrip", text).is_ok()
}

test "invalid UTF-8 and over-capacity text reads leave empty values" (env: Env) {
    let fs = env.fs
    var raw_path: Path = list {}
    discard raw_path.push(255)
    expect fs.write("invalid", raw_path).is_ok()

    var raw: Bytes max 8 = b"before"
    expect fs.read("invalid", raw).is_ok()
    expect raw.len() == 1L
    expect raw.to_text().is_err()

    var text: Text max 3 = "old"
    match fs.read("invalid", text) {
        err(error) => {
            match error {
                InvalidUtf8 => {},
                _ => { expect false }
            }
        },
        _ => { expect false }
    }
    expect text.len() == 0L

    expect fs.write("too-long", "😀abc").is_ok()
    match fs.read("too-long", text) {
        err(too_large_error) => { expect text.len() == 0L },
        _ => { expect false }
    }
}
