// Etc::Sieve: sieve of Eratosthenes up to `limit`, `iterations` times; sums (last prime + count).
const TEST_LIMIT: long = 1000L
const TEST_ITERATIONS: long = 3L
const RUN_LIMIT: long = 3000000L
const RUN_ITERATIONS: long = 270L
const MODULUS: long = 4294967296L

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// The largest s with s * s <= limit.
fn integer_sqrt(limit: long) -> long {
    var s = 0L
    for candidate: long in 1L..=limit {
        if candidate * candidate > limit { break }
        s = candidate
    }
    s
}

fn sieve(limit: long) -> long {
    var primes: bool[3000001] = fill(true)
    primes[0L] = false
    primes[1L] = false
    let sqrt_limit = integer_sqrt(limit)
    for p: long in 2L..=sqrt_limit {
        if primes[p] {
            let start = p * p
            let steps = (limit - start) / p + 1L
            for k: long in 0L..steps {
                primes[start + k * p] = false
            }
        }
    }
    var last_prime = 2L
    var count = 1L
    let odds = (limit - 3L) / 2L + 1L
    for k: long in 0L..odds {
        let n = 3L + k * 2L
        if primes[n] {
            last_prime = n
            count += 1L
        }
    }
    last_prime + count
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let limit = if run { RUN_LIMIT } else { TEST_LIMIT }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var checksum = 0L
    for _round: long in 0L..(warmup + iterations) {
        checksum = (checksum + sieve(limit)) % MODULUS
    }
    print(checksum)
}
