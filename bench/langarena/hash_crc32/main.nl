// LangArena Hash::CRC32: bitwise CRC-32 of a random buffer, run after changing one random byte per iteration.
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

fn crc32(data: list<byte, 1200000>) -> long {
    var crc = MASK32
    for i: long in 0L..data.count() {
        crc = crc ^ data[i].to_long()
        for _bit: long in 0L..8L {
            if (crc & 1L) != 0L {
                crc = (crc >> 1L) ^ 0xEDB88320L
            } else {
                crc = crc >> 1L
            }
        }
    }
    crc ^ MASK32
}

fn run_once(data: write list<byte, 1200000>, seed: write long, result: long) -> long {
    let ch = (int)next_int(seed, 256L)
    let at = next_int(seed, data.count())
    data[at] = (Octet)(ch)
    (result + crc32(data)) & MASK32
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let size = if run_mode { 1200000L } else { 1000L }
    let iterations = if run_mode { 98L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    var seed = 42L
    var data: list<byte, 1200000> = list {}
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
