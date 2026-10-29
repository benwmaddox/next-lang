// LangArena Hash::SHA256: a simple 8-lane multiply-shift hash of a random buffer
// (not the real SHA-256), run after changing one random byte per iteration.
type Octet = byte
const MASK32: long = 4294967295L

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn next_int(seed: write long, max_value: long) -> long {
    seed = (seed * 3877L + 29573L) % 139968L
    (seed * max_value) / 139968L
}

fn digest_word(data: list<byte, 1100000>) -> long {
    var hashes: long[8] = fill(0L)
    hashes[0L] = 0x6a09e667L
    hashes[1L] = 0xbb67ae85L
    hashes[2L] = 0x3c6ef372L
    hashes[3L] = 0xa54ff53aL
    hashes[4L] = 0x510e527fL
    hashes[5L] = 0x9b05688cL
    hashes[6L] = 0x1f83d9abL
    hashes[7L] = 0x5be0cd19L
    for i: long in 0L..data.count() {
        let lane = i & 7L
        var h = hashes[lane]
        h = ((h << 5L) + h + data[i].to_long()) & MASK32
        h = ((h + (h << 10L)) & MASK32) ^ (h >> 6L)
        hashes[lane] = h
    }
    // Write all 32 digest bytes (each lane big-endian), as the reference does.
    var digest: long[32] = fill(0L)
    for lane_index: long in 0L..8L {
        let word = hashes[lane_index]
        digest[lane_index * 4L] = (word >> 24L) & 255L
        digest[lane_index * 4L + 1L] = (word >> 16L) & 255L
        digest[lane_index * 4L + 2L] = (word >> 8L) & 255L
        digest[lane_index * 4L + 3L] = word & 255L
    }
    // The reference reads the first four digest bytes back as a little-endian u32.
    digest[0L] | (digest[1L] << 8L) | (digest[2L] << 16L) | (digest[3L] << 24L)
}

fn run_once(data: write list<byte, 1100000>, seed: write long, result: long) -> long {
    let ch = (int)next_int(seed, 256L)
    let at = next_int(seed, data.count())
    data[at] = (Octet)(ch)
    (result + digest_word(data)) & MASK32
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let prep = is_prep_mode(env)
    let size = if run_mode { 1100000L } else { 100L }
    let iterations = if run_mode { 1200L } else { 50L }
    let warmup = max(iterations / 5L, 1L)

    var seed = 42L
    var data: list<byte, 1100000> = list {}
    for _i: long in 0L..size {
        discard data.push((Octet)((int)next_int(seed, 256L)))
    }

    // LangArena: prepare, warm up, reset the generator, then the timed iterations.
    // Prep mode stops after the warmup rounds.
    var result = 0L
    for _w: long in 0L..warmup {
        result = run_once(data, seed, result)
    }
    if prep {
        print(result)
    } else {
        seed = 42L
        for _r: long in 0L..iterations {
            result = run_once(data, seed, result)
        }
        print(result)
    }
}
