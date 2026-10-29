fn fit_or_zero(value: int) -> byte {
    match value.fit<byte>() {
        some(byte_value) => byte_value,
        none => 0,
    }
}

fn main() {
    print(fit_or_zero(-1).to_long())
    print(fit_or_zero(0).to_long())
    print(fit_or_zero(127).to_long())
    print(fit_or_zero(128).to_long())
    print(fit_or_zero(255).to_long())
    print(fit_or_zero(256).to_long())

    let raw: Bytes max 4 = b"\x00\x7f\x80\xff"
    for index in 0L..raw.count() { print(raw[index].to_long()) }
    let utf8: Bytes max 2 = b"\xc3\xa9"
    match utf8.to_text() {
        ok(text) => print(text),
        err(_) => print("invalid UTF-8"),
    }
}
