fn first_byte(value: Bytes max 8) -> byte {
    value[0L]
}

fn main() {
    let word: Ascii max 8 = "hello"
    print(word[1L])
    for value in word {
        print(value)
    }
    print(word.slice(1L..4L))
    print(word.slice(1L..=2L))
    print(word.contains("ell"))
    print(word.starts_with("hel"))
    print(word.starts_with("ell"))
    print(first_byte(word.bytes()))
}
