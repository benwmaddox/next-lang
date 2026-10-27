// LangArena Compress::ArithEncode: 32-bit arithmetic coding with a static frequency table.
type Octet = int 0..=255
const HALF: long = 0x80000000L
const QUARTER: long = 0x40000000L
const THREE_QUARTERS: long = 0xC0000000L

struct Encoded {
    data: Bytes max 200008
    frequencies: long[256]
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn generate_test_data(size: long) -> list<byte, 100004> {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: list<byte, 100004> = list {}
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

fn write_bit(out: grow Bytes max 200008, buffer: write long, bit_pos: write long, bit: long) {
    buffer = buffer * 2L + (bit & 1L)
    bit_pos += 1L
    if bit_pos == 8L {
        discard out.push((Octet)((int)buffer))
        buffer = 0L
        bit_pos = 0L
    }
}

fn arith_encode(data: list<byte, 100004>) -> Encoded {
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

    var out: Bytes max 200008 = Bytes.empty()
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

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let size = if run_mode { 100004L } else { 54L }
    let iterations = if run_mode { 500L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    let test_data = generate_test_data(size)
    var result = 0L
    for _w: long in 0L..warmup + iterations {
        let encoded = arith_encode(test_data)
        result = (result + encoded.data.count()) % 4294967296L
    }
    print(result)
}
