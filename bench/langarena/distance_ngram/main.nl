// LangArena Distance::NGram: 4-gram overlap of random string pairs over "abcdefghij".
// The score is a double (step F1: floats); the checksum sums score * 1000 truncated.
type Octet = byte
const GRAM: long = 4L

struct Pair {
    first: Bytes max 20004
    second: Bytes max 20004
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn next_int(seed: write long, max: long) -> long {
    seed = (seed * 3877L + 29573L) % 139968L
    (seed * max) / 139968L
}

fn random_string(seed: write long, length: long) -> Bytes max 20004 {
    var text: Bytes max 20004 = Bytes.empty()
    for _i: long in 0L..length {
        discard text.push((Octet)((int)(97L + next_int(seed, 10L))))
    }
    text
}

fn generate_pairs(pairs: write list<Pair, 10>, count_pairs: long, size: long) {
    var seed = 42L
    for _p: long in 0L..count_pairs {
        let length1 = next_int(seed, size) + 4L
        let length2 = next_int(seed, size) + 4L
        let first = random_string(seed, length1)
        let second = random_string(seed, length2)
        discard pairs.push(Pair { first: first, second: second })
    }
}

fn gram_at(text: Bytes max 20004, i: long) -> long {
    (text[i].to_long() << 24L) | (text[i + 1L].to_long() << 16L) | (text[i + 2L].to_long() << 8L) | text[i + 3L].to_long()
}

fn ngram(first: Bytes max 20004, second: Bytes max 20004) -> double {
    let length1 = first.count()
    let length2 = second.count()
    if length1 < GRAM || length2 < GRAM {
        return 0.0
    }

    var grams1: map<long, long, 16384> = map {}
    for i: long in 0L..length1 - GRAM + 1L {
        let gram = gram_at(first, i)
        grams1.set(gram, (grams1.get(gram) ?? 0L) + 1L).unwrap()
    }

    var grams2: map<long, long, 16384> = map {}
    var intersection = 0L
    for i: long in 0L..length2 - GRAM + 1L {
        let gram = gram_at(second, i)
        let seen = (grams2.get(gram) ?? 0L) + 1L
        grams2.set(gram, seen).unwrap()
        match grams1.get(gram) {
            some(seen_first) => {
                if seen <= seen_first {
                    intersection += 1L
                }
            }
            none => {}
        }
    }

    let total = grams1.count() + grams2.count()
    if total > 0L {
        intersection.to_double() / total.to_double()
    } else {
        0.0
    }
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let count_pairs = if run_mode { 10L } else { 2L }
    let size = if run_mode { 20000L } else { 500L }
    let iterations = if run_mode { 100L } else { 1L }
    let warmup = max(iterations / 5L, 1L)

    var pairs: list<Pair, 10> = list {}
    generate_pairs(pairs, count_pairs, size)
    var result = 0L
    for _w: long in 0L..warmup + iterations {
        for pair in pairs {
            result = (result + (long)(ngram(pair.first, pair.second) * 1000.0)) % 4294967296L
        }
    }
    print(result)
}
