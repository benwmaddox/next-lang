struct Token {
    text: Ascii max 32
}

fn main() {
    var checksum = 0L
    var seed = 1L

    for _batch: long in 0L..20000L {
        var tokens: list<Token, 2048> = list {}

        for _i: long in 0L..2048L {
            seed = (seed * 1103515245L + 12345L) % 2147483648L
            let word_idx = seed % 10L

            let word: Ascii max 32 = match word_idx {
                0L => "apple"
                1L => "banana"
                2L => "cherry"
                3L => "dragon"
                4L => "eagle"
                5L => "forest"
                6L => "garden"
                7L => "house"
                8L => "island"
                _ => "zebra"
            }

            discard tokens.push(Token { text: word })
        }

        for token in tokens {
            let tlen: int = (int)token.text.len()
            checksum = (checksum * 31L + tlen.to_long()) % 1000000007L
        }
    }

    print(checksum)
}
