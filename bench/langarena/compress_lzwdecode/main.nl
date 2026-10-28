// LangArena Compress::LZWDecode: decode LZW with 16-bit codes. Dictionary phrases are
// (start, length) spans into one growing byte arena.
type Octet = int 0..=255

struct Span {
    start: long
    length: long
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn generate_test_data(size: long) -> Bytes max 1000007 {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: Bytes max 1000007 = Bytes.empty()
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

fn push_code(out: grow Bytes max 2000014, code: long) {
    discard out.push((Octet)((int)((code >> 8L) & 255L)))
    discard out.push((Octet)((int)(code & 255L)))
}

fn lzw_encode(input: Bytes max 1000007) -> Bytes max 2000014 {
    var out: Bytes max 2000014 = Bytes.empty()
    if input.count() == 0L {
        return out
    }
    var dict: map<long, long, 32768> = map {}
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

fn lzw_decode(encoded: Bytes max 2000014) -> Bytes max 1000007 {
    var result: Bytes max 1000007 = Bytes.empty()
    if encoded.count() == 0L {
        return result
    }
    var arena: Bytes max 1100000 = Bytes.empty()
    var spans: list<Span, 32768> = list {}
    for i: long in 0L..256L {
        discard arena.push((Octet)((int)i))
        discard spans.push(Span { start: i, length: 1L })
    }

    var old_code = encoded[0L].to_long() * 256L + encoded[1L].to_long()
    discard result.try_append(arena.slice(spans[old_code].start..spans[old_code].start + spans[old_code].length))

    for pair: long in 1L..encoded.count() / 2L {
        let new_code = encoded[pair * 2L].to_long() * 256L + encoded[pair * 2L + 1L].to_long()
        let old_span = spans[old_code]
        if new_code > spans.count() {
            return Bytes.empty()
        }
        let first_byte = if new_code < spans.count() { arena[spans[new_code].start] } else { arena[old_span.start] }
        let entry_start = arena.count()
        discard arena.try_append(arena.slice(old_span.start..old_span.start + old_span.length))
        discard arena.push(first_byte)
        discard spans.push(Span { start: entry_start, length: old_span.length + 1L })
        let span = spans[new_code]
        discard result.try_append(arena.slice(span.start..span.start + span.length))
        old_code = new_code
    }
    result
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let prep = is_prep_mode(env)
    let size = if run_mode { 1000007L } else { 61L }
    let iterations = if run_mode { 1600L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    // Prepare once (untimed), then warmup rounds; prep mode stops after warmup.
    let test_data = generate_test_data(size)
    let encoded = lzw_encode(test_data)
    let rounds = if prep { warmup } else { warmup + iterations }
    var result = 0L
    var decoded: Bytes max 1000007 = Bytes.empty()
    for _w: long in 0L..rounds {
        decoded = lzw_decode(encoded)
        result = (result + decoded.count()) % 4294967296L
    }
    if decoded == test_data {
        result = (result + 100000L) % 4294967296L
    }
    print(result)
}
