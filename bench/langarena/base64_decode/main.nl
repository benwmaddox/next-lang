// Base64::Decode: decode the Base64 of `size` bytes of 'a', `iterations` times.
const TEST_SIZE: long = 23L
const TEST_ITERATIONS: long = 8192L
const RUN_SIZE: long = 500000L
const RUN_ITERATIONS: long = 4000L
const MODULUS: long = 4294967296L
const ALPHABET: Bytes max 64 = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const PAD: byte = 61

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn sextet(value: long) -> byte {
    ALPHABET[value]
}

fn encode(data: Bytes max 500000, out: grow Bytes max 700000) {
    let size = data.len()
    let groups = size / 3L
    for g: long in 0L..groups {
        let at = g * 3L
        let n = data[at].to_long() * 65536L + data[at + 1L].to_long() * 256L + data[at + 2L].to_long()
        out.push(sextet(n / 262144L)).unwrap()
        out.push(sextet((n / 4096L) % 64L)).unwrap()
        out.push(sextet((n / 64L) % 64L)).unwrap()
        out.push(sextet(n % 64L)).unwrap()
    }
    let rest = size - groups * 3L
    if rest == 1L {
        let n = data[groups * 3L].to_long() * 65536L
        out.push(sextet(n / 262144L)).unwrap()
        out.push(sextet((n / 4096L) % 64L)).unwrap()
        out.push(PAD).unwrap()
        out.push(PAD).unwrap()
    } else if rest == 2L {
        let n = data[groups * 3L].to_long() * 65536L + data[groups * 3L + 1L].to_long() * 256L
        out.push(sextet(n / 262144L)).unwrap()
        out.push(sextet((n / 4096L) % 64L)).unwrap()
        out.push(sextet((n / 64L) % 64L)).unwrap()
        out.push(PAD).unwrap()
    } else {}
}

// Decodes padded standard Base64; none if the text is malformed.
fn decode(text: Bytes max 700000, table: int[256], out: grow Bytes max 500000) -> Option<long> {
    let size = text.len()
    if size % 4L != 0L { return none }
    var padding = 0L
    if size > 0L {
        if text[size - 1L] == PAD { padding = 1L }
        if size > 1L {
            if text[size - 2L] == PAD { padding = 2L }
        }
    }
    let quads = size / 4L
    for q: long in 0L..quads {
        let at = q * 4L
        let a = table[text[at].to_long()]
        let b = table[text[at + 1L].to_long()]
        var c = 0
        var d = 0
        if q == quads - 1L {
            if padding == 0L {
                c = table[text[at + 2L].to_long()]
                d = table[text[at + 3L].to_long()]
            } else if padding == 1L {
                c = table[text[at + 2L].to_long()]
            } else {}
        } else {
            c = table[text[at + 2L].to_long()]
            d = table[text[at + 3L].to_long()]
        }
        if a < 0 || b < 0 || c < 0 || d < 0 { return none }
        let n = a.to_long() * 262144L + b.to_long() * 4096L + c.to_long() * 64L + d.to_long()
        out.push(clamp((int)(n / 65536L), 0, 255)).unwrap()
        if q < quads - 1L || padding < 2L {
            out.push(clamp((int)((n / 256L) % 256L), 0, 255)).unwrap()
        }
        if q < quads - 1L || padding < 1L {
            out.push(clamp((int)(n % 256L), 0, 255)).unwrap()
        }
    }
    some(out.len())
}

fn checksum_bytes(text: Bytes max 100) -> long {
    var hash = 5381L
    for i: long in 0L..text.len() {
        hash = (hash * 33L + text[i].to_long()) % MODULUS
    }
    hash
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let size = if run { RUN_SIZE } else { TEST_SIZE }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    let prep = is_prep_mode(env)
    let rounds = if prep { warmup } else { warmup + iterations }
    var table: int[256] = fill(-1)
    for i: long in 0L..64L { table[ALPHABET[i].to_long()] = (int)i }

    var data: Bytes max 500000 = Bytes.empty()
    for _i: long in 0L..size { data.push(97).unwrap() }
    var encoded: Bytes max 700000 = Bytes.empty()
    encode(data, encoded)

    var result = 0L
    var decoded: Bytes max 500000 = Bytes.empty()
    for _round: long in 0L..rounds {
        decoded = Bytes.empty()
        let length = decode(encoded, table, decoded).unwrap()
        result = (result + length) % MODULUS
    }
    // "decode <first four of encoded>... to <first four of decoded>...: <result>"
    var message: Bytes max 100 = b"decode "
    for i: long in 0L..4L { message.push(encoded[i]).unwrap() }
    message.try_append(b"... to ").unwrap()
    for i: long in 0L..4L { message.push(decoded[i]).unwrap() }
    message.try_append(b"...: ").unwrap()
    message.try_append(str(result).bytes()).unwrap()
    print(checksum_bytes(message))
}
