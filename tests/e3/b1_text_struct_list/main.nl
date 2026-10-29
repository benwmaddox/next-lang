struct Token {
    kind: int
    text: Ascii max 8
    weight: long
}

fn main() {
    var tokens: list<Token, 4> = list {}
    discard tokens.push(Token { kind: 1, text: "abc", weight: 10L })
    discard tokens.push(Token { kind: 2, text: "defgh", weight: 20L })
    print(tokens.count())
    print(tokens[0L].kind)
    print(tokens[1L].text.len())
    print(tokens[1L].weight)
    let t = tokens[1L]
    print(t.text.len() + (long)t.kind)
    print((int)t.text.bytes()[2L])
}
