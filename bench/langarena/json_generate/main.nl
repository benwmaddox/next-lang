// LangArena Json::Generate: build coordinates, then serialise them to JSON text repeatedly.
//
// The reference holds f64 coordinates, each rounded to 8 decimals, and serde_json prints the
// shortest text that reads back as the same double. Every value here is last / 139968 rounded to
// 8 decimals, so it is exactly m / 10^8 for an integer m, and its shortest text is m's digits
// with trailing zeros dropped (ryu's layout: plain from 1e-5 up, otherwise d.ddde-x). So the
// coordinates are kept as integers in units of 1e-8 and printed from them, which gives the same
// bytes without floats. The name's "{:.7}" is the same idea in units of 1e-7.
const MAX_TEXT: long = 4194304L     // about 2.2 MB at the run size

struct Rng { last: long }

struct Coordinate {
    x: long    // in units of 1e-8
    y: long
    z: long
    name: Bytes max 64
}

fn next_int(rng: write Rng, max_value: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max_value / 139968L
}

// next_float(1.0) rounded to a whole number of `unit`ths (exact: no tie can occur for this generator).
fn next_scaled(rng: write Rng, unit: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    (rng.last * unit * 2L + 139968L) / (2L * 139968L)
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// A second argument ("run prep" / "test prep") runs prepare plus the warmup rounds only.
fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn put(out: grow Bytes max 4194304, piece: Bytes max 64) {
    discard out.try_append(piece)
}

// value >= 0, zero-padded on the left to at least `width_value` digits.
fn put_number(out: grow Bytes max 4194304, value: long, width_value: long) {
    var digits: list<int, 24> = list {}
    var rest = value
    for _d in 0L..20L {
        discard digits.push((int)(48L + rest % 10L))
        rest = rest / 10L
        if rest == 0L { break }
    }
    for _pad in 0L..24L {
        if digits.count() >= width_value { break }
        discard digits.push(48)
    }
    for k in 0L..digits.count() {
        discard out.push(digits[digits.count() - 1L - k])
    }
}

// A value m * 10^-8 (0 <= m <= 10^8) the way serde_json prints the double.
fn put_float8(out: grow Bytes max 4194304, m: long) {
    if m == 0L {
        put(out, b"0.0")
        return
    }
    if m == 100000000L {
        put(out, b"1.0")
        return
    }
    var digits = m
    var exponent = -8L
    for _z in 0L..8L {
        if digits % 10L != 0L { break }
        digits = digits / 10L
        exponent += 1L
    }
    var text: list<int, 24> = list {}
    var rest = digits
    for _d in 0L..20L {
        discard text.push((int)(48L + rest % 10L))
        rest = rest / 10L
        if rest == 0L { break }
    }
    let length = text.count()
    let point = length + exponent         // digits before the decimal point
    if point > 0L {
        for k in 0L..length {
            if k == point { put(out, b".") }
            discard out.push(text[length - 1L - k])
        }
    } else if point > -5L {
        put(out, b"0.")
        for _zero in 0L..(0L - point) { put(out, b"0") }
        for k in 0L..length { discard out.push(text[length - 1L - k]) }
    } else {
        for k in 0L..length {
            if k == 1L { put(out, b".") }
            discard out.push(text[length - 1L - k])
        }
        put(out, b"e-")
        put_number(out, 1L - point, 0L)
    }
}

fn make_name(rng: write Rng) -> Bytes max 64 {
    var name: Bytes max 64 = Bytes.empty()
    let scaled = next_scaled(rng, 10000000L)
    let suffix = next_int(rng, 10000L)
    put_name(name, scaled, suffix)
    name
}

fn put_name(name: grow Bytes max 64, scaled: long, suffix: long) {
    var digits: list<int, 24> = list {}
    discard digits.push((int)(48L + scaled / 10000000L))
    discard digits.push(46)
    var frac = scaled % 10000000L
    var place = 1000000L
    for _d in 0L..7L {
        discard digits.push((int)(48L + frac / place))
        frac = frac % place
        place = place / 10L
    }
    discard digits.push(32)
    var tail: list<int, 24> = list {}
    var rest = suffix
    for _d in 0L..20L {
        discard tail.push((int)(48L + rest % 10L))
        rest = rest / 10L
        if rest == 0L { break }
    }
    for k in 0L..digits.count() { discard name.push(digits[k]) }
    for k in 0L..tail.count() { discard name.push(tail[tail.count() - 1L - k]) }
}

fn prepare(data: write list<Coordinate, 20000>, rng: write Rng, n: long) {
    for _i in 0L..n {
        let x = next_scaled(rng, 100000000L)
        let y = next_scaled(rng, 100000000L)
        let z = next_scaled(rng, 100000000L)
        let name = make_name(rng)
        discard data.push(Coordinate { x, y, z, name })
    }
}

fn put_coordinate(out: grow Bytes max 4194304, c: Coordinate) {
    put(out, b"{\"x\":")
    put_float8(out, c.x)
    put(out, b",\"y\":")
    put_float8(out, c.y)
    put(out, b",\"z\":")
    put_float8(out, c.z)
    put(out, b",\"name\":\"")
    discard out.try_append(c.name)
    put(out, b"\",\"opts\":{\"1\":[1,true]}}")
}

fn serialize(out: grow Bytes max 4194304, data: list<Coordinate, 20000>) {
    put(out, b"{\"coordinates\":[")
    for index in 0L..data.count() {
        if index > 0L { put(out, b",") }
        put_coordinate(out, data[index])
    }
    put(out, b"],\"info\":\"some info\"}")
}

fn starts_with_coordinates(text: Bytes max 4194304) -> bool {
    let head: Bytes max 16 = b"{\"coordinates\":"
    if text.count() < head.count() { return false }
    for k in 0L..head.count() {
        if text[k] != head[k] { return false }
    }
    true
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let prep = is_prep_mode(env)
    let coords = if run { 20000L } else { 9L }
    let iterations = if run { 100L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    let rounds = if prep { warmup } else { warmup + iterations }

    var rng = Rng { last: 42L }
    var data: list<Coordinate, 20000> = list {}
    prepare(data, rng, coords)

    var result = 0L
    var text: Bytes max 4194304 = Bytes.empty()
    for _round in 0L..rounds {
        text = Bytes.empty()
        serialize(text, data)
        if starts_with_coordinates(text) { result += 1L }
    }
    print(result)
}
