const MINSTD: long = 16807L
const MODULUS: long = 2147483647L

fn r1(x: long) -> long {
    (x * MINSTD) % MODULUS
}

fn hash_at(s: long, i: long) -> long {
    r1(r1(s + i))
}


// Stands in for the reference's stdin read: the first argument is the seed
// selector. "0" means seed 1; any other decimal number selects another seed
// (the reference uses a random one there).
fn read_seed(env: Env) -> long {
    match env.args().get(0L) {
        some(argument) => {
            var m = 0L
            for i: long in 0L..argument.count() {
                let digit = argument.get(i).unwrap().to_long() - 48L
                m = (m * 10L + digit) % 2147483646L
            }
            if m == 0L { 1L } else { m + 1L }
        }
        none => 1L
    }
}

const VOCAB: (Ascii max 8)[8] = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog"]

fn main(env: Env) {
    let seed = read_seed(env)
    var counts: map<Ascii max 8, long, 8> = map {}
    for i: long in 0L..200000L {
        let word = VOCAB[hash_at(seed, i) % 8L]
        let seen = counts.get(word) ?? 0L
        counts.set(word, seen + 1L).unwrap()
    }
    var result = 0L
    for k: long in 0L..8L {
        result += (k + 1L) * (counts.get(VOCAB[k]) ?? 0L)
    }
    print(result)
}
