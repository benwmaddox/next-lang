fn main() {
    var words: list<Ascii max 8, 4> = list {}
    discard words.push("hi")
    discard words.push("there")
    words[1L] = "zz"
    print(words[1L].len())
    if words[0L] == "hi" { print(1) } else { print(0) }
    if words[1L] == "hi" { print(1) } else { print(0) }
    let last = words.pop() ?? "none"
    print(last.len())
    print(words.count())
}
