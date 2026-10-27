// LangArena Hash::SHA256: a simple 8-lane multiply-shift hash of a random buffer
// (not the real SHA-256), run after changing one random byte per iteration.
type Octet = int 0..=255
const MASK32: long = 4294967295L

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
    // First four digest bytes (big-endian words) read back as a little-endian u32.
    let first = hashes[0L]
    ((first >> 24L) & 255L) | (((first >> 16L) & 255L) << 8L) | (((first >> 8L) & 255L) << 16L) | ((first & 255L) << 24L)
}

fn run_once(data: write list<byte, 1100000>, seed: write long, result: long) -> long {
    let ch = (int)next_int(seed, 256L)
    let at = next_int(seed, data.count())
    data[at] = (Octet)(ch)
    (result + digest_word(data)) & MASK32
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let size = if run_mode { 1100000L } else { 100L }
    let iterations = if run_mode { 1200L } else { 50L }
    let warmup = max(iterations / 5L, 1L)

    var seed = 42L
    var data: list<byte, 1100000> = list {}
    for _i: long in 0L..size {
        discard data.push((Octet)((int)next_int(seed, 256L)))
    }

    // LangArena: prepare, warm up, reset the generator, then the timed iterations.
    var result = 0L
    for _w: long in 0L..warmup {
        result = run_once(data, seed, result)
    }
    seed = 42L
    for _r: long in 0L..iterations {
        result = run_once(data, seed, result)
    }
    print(result)
}
