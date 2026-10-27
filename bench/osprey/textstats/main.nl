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

// Stage 0 Ascii has no contains/starts_with, so these scan the bytes.
fn contains_byte(w: Ascii max 8, wanted: byte) -> bool {
    var found = false
    for k: long in 0L..w.len() {
        if w.bytes()[k] == wanted {
            found = true
        }
    }
    found
}

fn starts_with_byte(w: Ascii max 8, wanted: byte) -> bool {
    w.len() > 0L && w.bytes()[0L] == wanted
}

fn main(env: Env) {
    let seed = read_seed(env)
    var acc = 0L
    for i: long in 0L..200000L {
        let w = VOCAB[hash_at(seed, i) % 8L]
        acc += w.len()
        if contains_byte(w, 111) {
            acc += 7L
        }
        if starts_with_byte(w, 116) {
            acc += 3L
        }
    }
    print(acc)
}
