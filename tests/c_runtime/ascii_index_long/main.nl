fn main() {
    let word: Ascii max 8 = "hello"
    let i = 2L
    print(word[1L].to_byte())
    print(word[i].to_byte())
    print(word[i] == "l")
    print("l" == word[i])
    print(word[i] == "x")
    print(word[1L] < word[i])
    print(word[i])
    let by = word.to_bytes()
    print(by[i])
    print(by[1L])
    print(word.slice(i..i + 2L))
    var out: Ascii max 8 = ""
    var text: Text max 8 = "hé"
    discard out.push(word[i].to_byte() + 1)
    discard out.push(by[i + 1L])
    discard text.push(word[1L].to_byte() - 1)
    print(out)
    print(text)
    print(word.first())
    print(word.last())
    print(text.first())
    print(text.last())
}
