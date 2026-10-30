// LangArena Json::ParseDom: parse the generated JSON into a generic tree, then average x, y and z.
// Needs floats (step F1): `double` and, for the checksum, "{:.7}" formatting. Stage 0 can't build it.
// The tree is one list of nodes; a node's children are a first_child / next chain (no pointers).
// The text is generated exactly as in Json::Generate (see there for why that needs no floats).
const MAX_TEXT: long = 4194304L     // about 2.2 MB at the run size

struct Rng { last: long }

struct Coordinate {
    x: long    // in units of 1e-8
    y: long
    z: long
    name: Bytes max 64
}

fn next_int(rng: write Rng, max: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max / 139968L
}

// next_float(1.0) rounded to a whole number of `unit`ths (exact: no tie can occur for this generator).
fn next_scaled(rng: write Rng, unit: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    (rng.last * unit * 2L + 139968L) / (2L * 139968L)
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn put(out: grow Bytes max 4194304, piece: Bytes max 64) {
    discard out.try_append(piece)
}

// value >= 0, zero-padded on the left to at least `width` digits.
fn put_number(out: grow Bytes max 4194304, value: long, width: long) {
    var digits: list<int, 24> = list {}
    var rest = value
    for _d in 0L..20L {
        discard digits.push((int)(48L + rest % 10L))
        rest = rest / 10L
        if rest == 0L { break }
    }
    for _pad in 0L..24L {
        if digits.count() >= width { break }
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

fn prepare(data: write list<Coordinate, 10000>, rng: write Rng, n: long) {
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

fn serialize(out: grow Bytes max 4194304, data: list<Coordinate, 10000>) {
    put(out, b"{\"coordinates\":[")
    for index in 0L..data.count() {
        if index > 0L { put(out, b",") }
        put_coordinate(out, data[index])
    }
    put(out, b"],\"info\":\"some info\"}")
}


// ---- JSON reading (no escapes or unicode: the generated text never has them) ----

struct Reader {
    pos: long
    len: long
    cur: int
}

struct Span {
    start: long
    length: long
}

fn advance(r: write Reader, input: Bytes max 4194304) {
    r.pos += 1L
    r.cur = 0
    if r.pos < r.len { r.cur = input[r.pos] }
}

fn skip_whitespace(r: write Reader, input: Bytes max 4194304) {
    for _s in 0L..MAX_TEXT {
        if !(r.cur == 32 || r.cur == 10 || r.cur == 13 || r.cur == 9) { break }
        advance(r, input)
    }
}

// A string without escapes: returns the span between the quotes.
fn read_string(r: write Reader, input: Bytes max 4194304) -> Span {
    advance(r, input)    // opening quote
    let start = r.pos
    for _s in 0L..MAX_TEXT {
        if r.cur == 34 || r.cur == 0 { break }
        advance(r, input)
    }
    let span = Span { start, length: r.pos - start }
    advance(r, input)    // closing quote
    span
}

fn span_equals(input: Bytes max 4194304, span: Span, name: Bytes max 16) -> bool {
    if span.length != name.count() { return false }
    for k in 0L..span.length {
        if input[span.start + k] != name[k] { return false }
    }
    true
}

fn is_digit(byte: int) -> bool { byte >= 48 && byte <= 57 }

// A JSON number as the nearest double: the digits as an integer mantissa, then one division or
// multiplication by an exactly representable power of ten (at most 22 places), so a single rounding.
fn read_number(r: write Reader, input: Bytes max 4194304) -> double {
    var negative = false
    if r.cur == 45 {
        negative = true
        advance(r, input)
    }
    var mantissa = 0L
    var exponent = 0L
    var seen_digits = 0L
    for _s in 0L..MAX_TEXT {
        if !is_digit(r.cur) { break }
        if seen_digits < 18L {
            mantissa = mantissa * 10L + (r.cur - 48).to_long()
            seen_digits += 1L
        } else {
            exponent += 1L
        }
        advance(r, input)
    }
    if r.cur == 46 {
        advance(r, input)
        for _s in 0L..MAX_TEXT {
            if !is_digit(r.cur) { break }
            if seen_digits < 18L {
                mantissa = mantissa * 10L + (r.cur - 48).to_long()
                seen_digits += 1L
                exponent -= 1L
            }
            advance(r, input)
        }
    }
    if r.cur == 101 || r.cur == 69 {
        advance(r, input)
        var exponent_negative = false
        if r.cur == 45 {
            exponent_negative = true
            advance(r, input)
        }
        if r.cur == 43 { advance(r, input) }
        var written = 0L
        for _s in 0L..8L {
            if !is_digit(r.cur) { break }
            written = written * 10L + (r.cur - 48).to_long()
            advance(r, input)
        }
        if exponent_negative { exponent -= written } else { exponent += written }
    }
    var scale = 1.0
    for _p in 0L..abs(exponent) { scale = scale * 10.0 }
    var value = (double)mantissa
    if exponent < 0L { value = value / scale } else { value = value * scale }
    if negative { 0.0 - value } else { value }
}

// The reference's helper::checksum_f64: djb2 over the "{:.7}" text of the value (0 <= value < 10).
// TODO(F1): replace the digit loop with str_fixed(value, 7) once floats and it exist.
fn checksum_f64(value: double) -> long {
    let scaled = (long)(value * 10000000.0 + 0.5)
    var hash = 5381L
    hash = (hash * 33L + 48L + scaled / 10000000L) % 4294967296L
    hash = (hash * 33L + 46L) % 4294967296L
    var place = 1000000L
    var rest = scaled % 10000000L
    for _d in 0L..7L {
        hash = (hash * 33L + 48L + rest / place) % 4294967296L
        rest = rest % place
        place = place / 10L
    }
    hash
}

const NULL: int = 0
const BOOL: int = 1
const NUMBER: int = 2
const STRING: int = 3
const ARRAY: int = 4
const OBJECT: int = 5

struct JsonNode {
    kind: int
    number: double
    text: Span         // a STRING's contents
    key: Span          // the member name, when this node is an object member
    first_child: int   // -1 when none
    next: int          // next sibling, -1 at the end
}

fn new_node(kind: int) -> JsonNode {
    JsonNode { kind, number: 0.0, text: Span { start: 0L, length: 0L }, key: Span { start: 0L, length: 0L }, first_child: -1, next: -1 }
}

recursive fn parse_value(r: write Reader, input: Bytes max 4194304, nodes: write list<JsonNode, 120000>) -> long {
    skip_whitespace(r, input)
    var node = new_node(NULL)
    if r.cur == 123 {
        node.kind = OBJECT
        advance(r, input)
        let id = nodes.count()
        discard nodes.push(node)
        var last = -1L
        for _member in 0L..MAX_TEXT {
            skip_whitespace(r, input)
            if r.cur == 125 || r.cur == 0 { break }
            if r.cur == 44 {
                advance(r, input)
                continue
            }
            let key = read_string(r, input)
            skip_whitespace(r, input)
            advance(r, input)    // ':'
            let child = parse_value(r, input, nodes)
            nodes[child].key = key
            if last < 0L { nodes[id].first_child = (int)child } else { nodes[last].next = (int)child }
            last = child
        }
        advance(r, input)
        return id
    }
    if r.cur == 91 {
        node.kind = ARRAY
        advance(r, input)
        let id = nodes.count()
        discard nodes.push(node)
        var last = -1L
        for _element in 0L..MAX_TEXT {
            skip_whitespace(r, input)
            if r.cur == 93 || r.cur == 0 { break }
            if r.cur == 44 {
                advance(r, input)
                continue
            }
            let child = parse_value(r, input, nodes)
            if last < 0L { nodes[id].first_child = (int)child } else { nodes[last].next = (int)child }
            last = child
        }
        advance(r, input)
        return id
    }
    if r.cur == 34 {
        node.kind = STRING
        node.text = read_string(r, input)
    } else if r.cur == 116 {            // true
        node.kind = BOOL
        for _c in 0L..4L { advance(r, input) }
    } else if r.cur == 102 {            // false
        node.kind = BOOL
        for _c in 0L..5L { advance(r, input) }
    } else if r.cur == 110 {            // null
        for _c in 0L..4L { advance(r, input) }
    } else {
        node.kind = NUMBER
        node.number = read_number(r, input)
    }
    let id = nodes.count()
    discard nodes.push(node)
    id
}

// The member of an object with the given name, or -1.
fn member(nodes: list<JsonNode, 120000>, input: Bytes max 4194304, object: long, name: Bytes max 16) -> long {
    var child = nodes[object].first_child.to_long()
    for _c in 0L..MAX_TEXT {
        if child < 0L { break }
        if span_equals(input, nodes[child].key, name) { return child }
        child = nodes[child].next.to_long()
    }
    -1L
}

struct Averages {
    x: double
    y: double
    z: double
}

// json["coordinates"] is an array of objects; average their "x", "y" and "z" numbers.
fn calc(input: Bytes max 4194304, nodes: write list<JsonNode, 120000>) -> Averages {
    nodes.clear()
    var reader = Reader { pos: 0L, len: input.count(), cur: 0 }
    if reader.len > 0L { reader.cur = input[0L] }
    let root = parse_value(reader, input, nodes)
    let coordinates = member(nodes, input, root, b"coordinates")
    var x = 0.0
    var y = 0.0
    var z = 0.0
    var total = 0L
    var coordinate = nodes[coordinates].first_child.to_long()
    for _c in 0L..MAX_TEXT {
        if coordinate < 0L { break }
        x += nodes[member(nodes, input, coordinate, b"x")].number
        y += nodes[member(nodes, input, coordinate, b"y")].number
        z += nodes[member(nodes, input, coordinate, b"z")].number
        total += 1L
        coordinate = nodes[coordinate].next.to_long()
    }
    let len = (double)total
    Averages { x: x / len, y: y / len, z: z / len }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let coords = if run { 10000L } else { 10L }
    let iterations = if run { 100L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var rng = Rng { last: 42L }
    var data: list<Coordinate, 10000> = list {}
    prepare(data, rng, coords)
    var text: Bytes max 4194304 = Bytes.empty()
    serialize(text, data)

    var nodes: list<JsonNode, 120000> = list {}
    var result = 0L
    let rounds = if is_prep_mode(env) { warmup } else { warmup + iterations }
    for _round in 0L..rounds {
        let averages = calc(text, nodes)
        let sum = checksum_f64(averages.x) + checksum_f64(averages.y) + checksum_f64(averages.z)
        result = (result + sum) % 4294967296L
    }
    print(result)
}
