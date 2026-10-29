fn main() {
    var words: list<Ascii max 8, 4> = list {}
    discard words.push("hi")
    discard words.push("there")
    discard words.push("a")
    print(words.count())
    print(words[0L].len())
    print(words[1L].len())
    print(words[2L].len())
    let w = words[1L]
    print(w.len())
    print((int)w.bytes()[0L])
}
