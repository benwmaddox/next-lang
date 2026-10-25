fn read_text(value: Text max 8 bytes max 32) -> Text max 16 bytes max 64 { value }
fn read_bytes(value: Bytes max 4) -> Bytes max 16 { value }

fn main() {
    let short: Text max 3 bytes max 12 = "aé"
    let wide: Text max 8 bytes max 32 = "b"
    print(short == wide)
    print(short != wide)
    print(short < wide)
    print(short <= wide)
    print(wide > short)
    print(wide >= short)
    let joined: Text max 11 bytes max 44 = short + wide
    print(joined)
    print(read_text(short))

    let small: Bytes max 2 = b"ab"
    let large: Bytes max 8 = b"ac"
    print(small == large)
    print(small != large)
    print(small < large)
    print(small <= large)
    print(large > small)
    print(large >= small)
    let joined_bytes: Bytes max 12 = small + large
    print(joined_bytes)
    print(read_bytes(small))
}
