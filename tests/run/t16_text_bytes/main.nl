fn read_text(value: Text max 8) -> long { value.len() }

fn main() {
    let text: Text max 3 = "a😀ß"
    print(text.len())
    print(text.byte_len())
    print(text.slice(1..3))
    print(text.upper())
    let ascii: Ascii max 8 = "plain"
    print(read_text(ascii))
    print(("x" + "ß").upper())

    let raw: Bytes max 8 = b"hello"
    print(raw.len())
    print(raw.to_text().unwrap())
    print(raw.to_ascii().unwrap())
    print("é".to_ascii().is_err())
    print("ascii".bytes().len())
    print(b"a" + b"bc")
    print((b"a" == b"a"))
}
