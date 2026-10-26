struct Token {
    text: String,
}

fn main() {
    let mut checksum: i64 = 0;
    let mut seed: i64 = 1;
    let mut tokens: Vec<Token> = Vec::with_capacity(2048);
    let mut word = String::with_capacity(32);

    for _batch in 0..20000 {
        tokens.clear();

        for _i in 0..2048 {
            seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
            let word_idx = seed % 10;

            word.clear();
            match word_idx {
                0 => word.push_str("apple"),
                1 => word.push_str("banana"),
                2 => word.push_str("cherry"),
                3 => word.push_str("dragon"),
                4 => word.push_str("eagle"),
                5 => word.push_str("forest"),
                6 => word.push_str("garden"),
                7 => word.push_str("house"),
                8 => word.push_str("island"),
                _ => word.push_str("zebra"),
            };

            tokens.push(Token { text: word.clone() });
        }

        for token in &tokens {
            let tlen = token.text.len() as i64;
            checksum = (checksum.wrapping_mul(31).wrapping_add(tlen)) % 1000000007;
        }
    }

    println!("{}", checksum);
}
