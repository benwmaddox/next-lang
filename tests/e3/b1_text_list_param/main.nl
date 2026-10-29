fn first_len(words: list<Ascii max 8, 4>) -> long {
    words[0L].len()
}
fn fill(words: write list<Ascii max 8, 4>) {
    discard words.push("abcdef")
    discard words.push("xy")
}
fn main() {
    var words: list<Ascii max 8, 4> = list {}
    fill(words)
    print(first_len(words))
    print(words.count())
}
