const GREETING: Ascii max 32 = "hello, world"
const PAD: byte = 61
const ALPHABET: Bytes max 8 = b"ABCDEFG"

fn length_of(text: Ascii max 32) -> long {
    text.len()
}

fn main() {
    let a: Ascii max 32 = GREETING
    let b: Ascii max 32 = GREETING
    print(a.len() + b.len())
    print(length_of(GREETING))
    print(GREETING.len())
    print(ALPHABET.len())
    print((int)ALPHABET[2L])
    print((int)PAD)
}
