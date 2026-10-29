// LangArena Compress::LZWEncode: LZW as the reference does it. The dictionary maps
// phrases to codes; each input byte extends the current phrase and probes the
// dictionary, emitting the current code and inserting the longer phrase on a miss.
// Phrases are Ascii keys, which hold bytes 0..127 only, so the dictionary is seeded
// with those 128 single-byte phrases (the test input is pure ASCII).
type Octet = byte

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

fn generate_test_data(size: long) -> Bytes max 200006 {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: Bytes max 200006 = Bytes.empty()
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

fn push_code(out: grow Bytes max 400012, code: long) {
    discard out.push((Octet)((int)((code >> 8L) & 255L)))
    discard out.push((Octet)((int)(code & 255L)))
}

fn char_key(value: long) -> Ascii max 256 {
    var key: Ascii max 256 = Ascii.empty()
    var one: Bytes max 1 = Bytes.empty()
    discard one.push((Octet)((int)value))
    key.try_append(one.to_ascii().unwrap()).unwrap()
    key
}

// The candidate phrase is the current phrase extended by one byte.
fn extend_key(prefix: Ascii max 256, value: long) -> Ascii max 256 {
    var key: Ascii max 256 = prefix
    var one: Bytes max 1 = Bytes.empty()
    discard one.push((Octet)((int)value))
    key.try_append(one.to_ascii().unwrap()).unwrap()
    key
}

fn lzw_encode(input: Bytes max 200006) -> Bytes max 400012 {
    var out: Bytes max 400012 = Bytes.empty()
    if input.count() == 0L {
        return out
    }
    var dict: map<Ascii max 256, long, 4096> = map {}
    for seed: long in 0L..128L {
        dict.set(char_key(seed), seed).unwrap()
    }
    var next_code = 256L
    var current = char_key(input[0L].to_long())
    for i: long in 1L..input.count() {
        let value = input[i].to_long()
        let candidate = extend_key(current, value)
        match dict.get(candidate) {
            some(_found) => {
                current = candidate
            }
            none => {
                // Every current phrase is in the dictionary, so the fallback 0L is unreachable.
                let code = match dict.get(current) {
                    some(found_code) => found_code,
                    none => 0L
                }
                push_code(out, code)
                dict.set(candidate, next_code).unwrap()
                next_code += 1L
                current = char_key(value)
            }
        }
    }
    let last = match dict.get(current) {
        some(found_code) => found_code,
        none => 0L
    }
    push_code(out, last)
    out
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let prep = is_prep_mode(env)
    let size = if run_mode { 200006L } else { 60L }
    let iterations = if run_mode { 85L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    // Prepare once (untimed), then warmup rounds; prep mode stops after warmup.
    let test_data = generate_test_data(size)
    let rounds = if prep { warmup } else { warmup + iterations }
    var result = 0L
    for _w: long in 0L..rounds {
        let encoded = lzw_encode(test_data)
        result = (result + encoded.count()) % 4294967296L
    }
    print(result)
}
