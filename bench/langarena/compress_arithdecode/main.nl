// LangArena Compress::ArithDecode: decode 32-bit arithmetic-coded data with a static frequency table.
type Octet = int 0..=255
const HALF: long = 0x80000000L
const QUARTER: long = 0x40000000L
const THREE_QUARTERS: long = 0xC0000000L

struct Encoded {
    data: Bytes max 200010
    frequencies: long[256]
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn generate_test_data(size: long) -> list<byte, 100005> {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: list<byte, 100005> = list {}
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

fn write_bit(out: grow Bytes max 200010, buffer: write long, bit_pos: write long, bit: long) {
    buffer = buffer * 2L + (bit & 1L)
    bit_pos += 1L
    if bit_pos == 8L {
        discard out.push((Octet)((int)buffer))
        buffer = 0L
        bit_pos = 0L
    }
}

fn arith_encode(data: list<byte, 100005>) -> Encoded {
    var frequencies: long[256] = fill(0L)
    for i: long in 0L..data.count() {
        frequencies[data[i].to_long()] += 1L
    }
    var total = 0L
    var low_table: long[256] = fill(0L)
    var high_table: long[256] = fill(0L)
    for symbol: long in 0L..256L {
        low_table[symbol] = total
        total += frequencies[symbol]
        high_table[symbol] = total
    }

    var out: Bytes max 200010 = Bytes.empty()
    var buffer = 0L
    var bit_pos = 0L
    var low = 0L
    var high = 0xFFFFFFFFL
    var pending = 0L
    for i: long in 0L..data.count() {
        let index = data[i].to_long()
        let range = high - low + 1L
        high = low + (range * high_table[index]) / total - 1L
        low = low + (range * low_table[index]) / total

        for _step: long in 0L..64L {
            if high < HALF {
                write_bit(out, buffer, bit_pos, 0L)
                for _p: long in 0L..pending {
                    write_bit(out, buffer, bit_pos, 1L)
                }
                pending = 0L
            } else if low >= HALF {
                write_bit(out, buffer, bit_pos, 1L)
                for _p: long in 0L..pending {
                    write_bit(out, buffer, bit_pos, 0L)
                }
                pending = 0L
                low -= HALF
                high -= HALF
            } else if low >= QUARTER && high < THREE_QUARTERS {
                pending += 1L
                low -= QUARTER
                high -= QUARTER
            } else {
                break
            }
            low = low * 2L
            high = (high * 2L + 1L) & 0xFFFFFFFFL
        }
    }

    pending += 1L
    if low < QUARTER {
        write_bit(out, buffer, bit_pos, 0L)
        for _p: long in 0L..pending {
            write_bit(out, buffer, bit_pos, 1L)
        }
    } else {
        write_bit(out, buffer, bit_pos, 1L)
        for _p: long in 0L..pending {
            write_bit(out, buffer, bit_pos, 0L)
        }
    }
    if bit_pos > 0L {
        buffer = buffer * (1L << (8L - bit_pos))
        discard out.push((Octet)((int)buffer))
    }
    Encoded { data: out, frequencies: frequencies }
}

fn read_bit(bytes_value: Bytes max 200010, byte_pos: write long, bit_pos: write long, current: write long) -> long {
    if bit_pos == 8L {
        byte_pos += 1L
        bit_pos = 0L
        current = if byte_pos < bytes_value.count() { bytes_value[byte_pos].to_long() } else { 0L }
    }
    let bit = (current >> (7L - bit_pos)) & 1L
    bit_pos += 1L
    bit
}

fn arith_decode(encoded: Encoded) -> list<byte, 100005> {
    var total = 0L
    var low_table: long[256] = fill(0L)
    var high_table: long[256] = fill(0L)
    for symbol: long in 0L..256L {
        low_table[symbol] = total
        total += encoded.frequencies[symbol]
        high_table[symbol] = total
    }

    var result: list<byte, 100005> = list {}
    var byte_pos = 0L
    var bit_pos = 0L
    var current = if encoded.data.count() > 0L { encoded.data[0L].to_long() } else { 0L }

    var value = 0L
    for _i: long in 0L..32L {
        value = value * 2L + read_bit(encoded.data, byte_pos, bit_pos, current)
    }

    var low = 0L
    var high = 0xFFFFFFFFL
    for _j: long in 0L..total {
        let range = high - low + 1L
        let scaled = ((value - low + 1L) * total - 1L) / range

        // First symbol whose cumulative high bound is above the scaled value.
        var first = 0L
        var past = 256L
        for _s: long in 0L..9L {
            if first >= past { break }
            let middle = (first + past) / 2L
            if high_table[middle] <= scaled {
                first = middle + 1L
            } else {
                past = middle
            }
        }
        let symbol = first
        discard result.push((Octet)((int)symbol))

        high = low + (range * high_table[symbol]) / total - 1L
        low = low + (range * low_table[symbol]) / total

        for _step: long in 0L..64L {
            if high >= HALF && low < HALF && (low < QUARTER || high >= THREE_QUARTERS) {
                break
            }
            let upper = high >= HALF && low >= HALF
            let middle = high >= HALF && low < HALF && low >= QUARTER && high < THREE_QUARTERS
            if upper {
                value -= HALF
                low -= HALF
                high -= HALF
            }
            if middle {
                value -= QUARTER
                low -= QUARTER
                high -= QUARTER
            }
            low = low * 2L
            high = high * 2L + 1L
            value = value * 2L + read_bit(encoded.data, byte_pos, bit_pos, current)
        }
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
    let size = if run_mode { 100005L } else { 55L }
    let iterations = if run_mode { 350L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    // Prepare once (untimed: test data and encoding); prep mode stops after warmup.
    let test_data = generate_test_data(size)
    let encoded = arith_encode(test_data)
    let rounds = if prep { warmup } else { warmup + iterations }
    var result = 0L
    var decoded: list<byte, 100005> = list {}
    for _w: long in 0L..rounds {
        decoded = arith_decode(encoded)
        result = (result + decoded.count()) % 4294967296L
    }
    if decoded == test_data {
        result = (result + 100000L) % 4294967296L
    }
    print(result)
}
