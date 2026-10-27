// LangArena CLBG::Fannkuchredux: pancake-flipping checksum and maximum flips over all permutations of n.
const MODULUS: long = 4294967296L

struct Flips {
    checksum: long
    max_flips: long
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn fannkuchredux(n: long) -> Flips {
    var perm1: long[32] = fill(0L)
    for i in 0L..32L { perm1[i] = i }
    var perm: long[32] = fill(0L)
    var counts: long[32] = fill(0L)
    var max_flips = 0L
    var perm_count = 0L
    var checksum = 0L
    var r = n

    for _perm in 0L..1000000000000L {
        for _fill in 0L..32L {
            if r <= 1L { break }
            counts[r - 1L] = r
            r -= 1L
        }

        for i in 0L..n { perm[i] = perm1[i] }

        var flips = 0L
        var k = perm[0L]
        for _flip in 0L..1000000L {
            if k == 0L { break }
            let k2 = (k + 1L) / 2L
            for i in 0L..k2 {
                let j = k - i
                let held = perm[i]
                perm[i] = perm[j]
                perm[j] = held
            }
            flips += 1L
            k = perm[0L]
        }

        if flips > max_flips { max_flips = flips }
        if perm_count % 2L == 0L { checksum += flips } else { checksum -= flips }

        for _next in 0L..64L {
            if r == n { return Flips { checksum, max_flips } }
            let perm0 = perm1[0L]
            for i in 0L..r {
                perm1[i] = perm1[i + 1L]
            }
            perm1[r] = perm0
            counts[r] -= 1L
            if counts[r] > 0L { break }
            r += 1L
        }
        perm_count += 1L
    }
    Flips { checksum, max_flips }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let n = if run { 8L } else { 5L }
    let iterations = if run { 700L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var result = 0L
    for _round in 0L..warmup + iterations {
        let flips = fannkuchredux(n)
        let low = (flips.checksum % MODULUS + MODULUS) % MODULUS    // the reference casts the i32 to u32
        result = (result + (low * 100L + flips.max_flips) % MODULUS) % MODULUS
    }
    print(result)
}
