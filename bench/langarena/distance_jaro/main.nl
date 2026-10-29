// LangArena Distance::Jaro: Jaro similarity of random string pairs over "abcdefghij".
// The score is a double (step F1: floats); the checksum sums score * 1000 truncated.
type Octet = byte

struct Pair {
    first: Bytes max 54
    second: Bytes max 54
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

fn random_string(seed: write long, length: long) -> Bytes max 54 {
    var text: Bytes max 54 = Bytes.empty()
    for _i: long in 0L..length {
        discard text.push((Octet)((int)(97L + next_int(seed, 10L))))
    }
    text
}

fn generate_pairs(count_pairs: long, size: long) -> list<Pair, 1000> {
    var seed = 42L
    var pairs: list<Pair, 1000> = list {}
    for _p: long in 0L..count_pairs {
        let length1 = next_int(seed, size) + 4L
        let length2 = next_int(seed, size) + 4L
        let first = random_string(seed, length1)
        let second = random_string(seed, length2)
        discard pairs.push(Pair { first: first, second: second })
    }
    pairs
}

fn jaro(first: Bytes max 54, second: Bytes max 54) -> double {
    let length1 = first.count()
    let length2 = second.count()
    if length1 == 0L || length2 == 0L {
        return 0.0
    }
    let match_dist = max(max(length1, length2) / 2L - 1L, 0L)

    var first_matches: bool[54] = fill(false)
    var second_matches: bool[54] = fill(false)
    var matches = 0L
    for i: long in 0L..length1 {
        let start = max(i - match_dist, 0L)
        let end = min(length2 - 1L, i + match_dist)
        for j: long in start..end + 1L {
            if !second_matches[j] && first[i] == second[j] {
                first_matches[i] = true
                second_matches[j] = true
                matches += 1L
                break
            }
        }
    }
    if matches == 0L {
        return 0.0
    }

    var transpositions = 0L
    var k = 0L
    for i: long in 0L..length1 {
        if first_matches[i] {
            for _skip: long in 0L..length2 {
                if k < length2 && !second_matches[k] {
                    k += 1L
                } else {
                    break
                }
            }
            if k < length2 {
                if first[i] != second[k] {
                    transpositions += 1L
                }
                k += 1L
            }
        }
    }
    transpositions = transpositions / 2L

    let m = matches.to_double()
    (m / length1.to_double() + m / length2.to_double() + (m - transpositions.to_double()) / m) / 3.0
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let count_pairs = if run_mode { 1000L } else { 10L }
    let size = if run_mode { 50L } else { 5L }
    let iterations = if run_mode { 780L } else { 1L }
    let warmup = max(iterations / 5L, 1L)

    let pairs = generate_pairs(count_pairs, size)
    var result = 0L
    for _w: long in 0L..warmup + iterations {
        for pair in pairs {
            result = (result + (long)(jaro(pair.first, pair.second) * 1000.0)) % 4294967296L
        }
    }
    print(result)
}
