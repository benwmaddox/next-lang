// Base64::Encode: encode `size` bytes of 'a' with standard padded Base64, `iterations` times.
const TEST_SIZE: long = 30L
const TEST_ITERATIONS: long = 8192L
const RUN_SIZE: long = 500000L
const RUN_ITERATIONS: long = 5000L
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

// Standard Base64 with '=' padding.
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

// djb2 over the bytes, as LangArena's checksum_str (u32).
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
    var data: Bytes max 500000 = Bytes.empty()
    for _i: long in 0L..size { data.push(97).unwrap() }
    var result = 0L
    var encoded: Bytes max 700000 = Bytes.empty()
    for _round: long in 0L..rounds {
        encoded = Bytes.empty()
        encode(data, encoded)
        result = (result + encoded.len()) % MODULUS
    }
    // "encode aaaa... to <first four>...: <result>" (the data and its encoding are longer than 4 here)
    var message: Bytes max 100 = b"encode aaaa... to "
    for i: long in 0L..4L { message.push(encoded[i]).unwrap() }
    message.try_append(b"...: ").unwrap()
    message.try_append(str(result).bytes()).unwrap()
    print(checksum_bytes(message))
}
