struct Token {
    text: String,
}

fn main() {
    let mut checksum: i64 = 0;
    let mut seed: i64 = 1;

    for _batch in 0..20000 {
        let mut tokens: Vec<Token> = Vec::new();

        for _i in 0..2048 {
            seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
            let word_idx = seed % 10;

            let word = match word_idx {
                0 => "apple".to_string(),
                1 => "banana".to_string(),
                2 => "cherry".to_string(),
                3 => "dragon".to_string(),
                4 => "eagle".to_string(),
                5 => "forest".to_string(),
                6 => "garden".to_string(),
                7 => "house".to_string(),
                8 => "island".to_string(),
                _ => "zebra".to_string(),
            };

            tokens.push(Token { text: word });
        }

        for token in &tokens {
            let tlen = token.text.len() as i64;
            checksum = (checksum.wrapping_mul(31).wrapping_add(tlen)) % 1000000007;
        }
    }

    println!("{}", checksum);
}
