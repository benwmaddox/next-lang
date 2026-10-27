// LangArena Compress::LZWEncode: LZW with 16-bit codes. The dictionary maps
// (code of the current phrase, next byte) to the code of the longer phrase.
type Octet = int 0..=255

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
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

fn lzw_encode(input: Bytes max 200006) -> Bytes max 400012 {
    var out: Bytes max 400012 = Bytes.empty()
    if input.count() == 0L {
        return out
    }
    var dict: map<long, long, 16384> = map {}
    var next_code = 256L
    var current = input[0L].to_long()
    for i: long in 1L..input.count() {
        let byte_value = input[i].to_long()
        let key = current * 256L + byte_value
        match dict.get(key) {
            some(code) => {
                current = code
            }
            none => {
                push_code(out, current)
                dict.set(key, next_code).unwrap()
                next_code += 1L
                current = byte_value
            }
        }
    }
    push_code(out, current)
    out
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let size = if run_mode { 200006L } else { 60L }
    let iterations = if run_mode { 85L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    let test_data = generate_test_data(size)
    var result = 0L
    for _w: long in 0L..warmup + iterations {
        let encoded = lzw_encode(test_data)
        result = (result + encoded.count()) % 4294967296L
    }
    print(result)
}
