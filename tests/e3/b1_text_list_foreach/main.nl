struct Token {
    text: Ascii max 32
}
fn main() {
    var tokens: list<Token, 3> = list {}
    let a: Ascii max 32 = "apple"
    let b: Ascii max 32 = "banana"
    discard tokens.push(Token { text: a })
    discard tokens.push(Token { text: b })
    discard tokens.push(Token { text: a })
    for token in tokens {
        print(token.text.len())
    }
    print(tokens[1L].text.len())
}
