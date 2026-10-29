struct Token {
    text: Ascii max 32
}
fn main() {
    var tokens: list<Token, 6> = list {}
    for i: long in 0L..6L {
        let word: Ascii max 32 = match i % 3L {
            0L => "apple"
            1L => "banana"
            _ => "zebra"
        }
        discard tokens.push(Token { text: word })
    }
    for token in tokens {
        print(token.text.len())
    }
}
