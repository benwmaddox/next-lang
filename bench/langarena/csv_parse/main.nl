// CSV::Parse: generate `rows` quoted CSV records from LangArena's LCG, then parse them and
// average three numeric columns, `iterations` times. Needs floats (step F1): `double`,
// `str_fixed(x, digits)` (Rust's {:.N}) and `parse_double()`.
const TEST_ROWS: long = 11L
const TEST_ITERATIONS: long = 3L
const RUN_ROWS: long = 100000L
const RUN_ITERATIONS: long = 70L
const MODULUS: long = 4294967296L
const IM: long = 139968L
const IA: long = 3877L
const IC: long = 29573L
const LCG_INIT: long = 42L

type Data = Bytes max 8000000

struct Point {
    x: double
    y: double
    z: double
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// LangArena's next_float(1.0): 1.0 * last / IM.
fn next_float(last: write long) -> double {
    last = (last * IA + IC) % IM
    (double)last / 139968.0
}

fn put(data: grow Bytes max 8000000, text: Ascii max 80) {
    data.try_append(text.bytes()).unwrap()
}

fn generate(data: grow Bytes max 8000000, rows: long) {
    var last = LCG_INIT
    for i: long in 0L..rows {
        let letter = (int)(65L + i % 26L)
        let x = next_float(last)
        let z = next_float(last)
        let y = next_float(last)
        let tag = i % 100L
        // "point A\n, ""5""", with a literal backslash and n inside the quotes
        data.push(34).unwrap()
        put(data, "point ")
        data.push(clamp(letter, 0, 255)).unwrap()
        put(data, "\\n, \"\"" + str(tag) + "\"\"\",")
        put(data, str_fixed(x, 10) + ",")
        put(data, ",")
        put(data, str_fixed(z, 10) + ",")
        let flag: Ascii max 8 = if i % 2L == 0L { "true" } else { "false" }
        put(data, "\"[" + flag + "\\n, " + str(tag) + "]\",")
        put(data, str_fixed(y, 10) + "\n")
    }
}

// The djb2 hash over bytes, as LangArena's checksum_str (u32).
fn checksum_data(data: Data) -> long {
    var hash = 5381L
    for i: long in 0L..data.len() {
        hash = (hash * 33L + data[i].to_long()) % MODULUS
    }
    hash
}

fn checksum_text(text: Ascii max 64) -> long {
    var hash = 5381L
    for i: long in 0L..text.len() {
        hash = (hash * 33L + text.bytes()[i].to_long()) % MODULUS
    }
    hash
}

fn checksum_double(value: double) -> long {
    checksum_text(str_fixed(value, 7))
}

fn field_double(data: Data, from: long, to: long) -> double {
    var digits: Bytes max 32 = Bytes.empty()
    for k: long in from..to { digits.push(data[k]).unwrap() }
    digits.to_ascii().unwrap().parse_double().unwrap()
}

// Splits records on newlines and fields on commas, honouring double quotes; keeps columns 1, 3 and 5.
fn parse_points(data: Data, points: write list<Point, 100000>) {
    var field = 0L
    var field_start = 0L
    var in_quotes = false
    var x = 0.0
    var y = 0.0
    var z = 0.0
    for i: long in 0L..data.len() {
        let c = data[i]
        if c == 34 {
            in_quotes = !in_quotes
        } else if !in_quotes && (c == 44 || c == 10) {
            if field == 1L { x = field_double(data, field_start, i) }
            if field == 3L { z = field_double(data, field_start, i) }
            if field == 5L { y = field_double(data, field_start, i) }
            field += 1L
            field_start = i + 1L
            if c == 10 {
                points.push(Point { x: x, y: y, z: z }).unwrap()
                field = 0L
            }
        } else {}
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let rows = if run { RUN_ROWS } else { TEST_ROWS }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var data: Data = Bytes.empty()
    generate(data, rows)
    var checksum = 0L
    for _round: long in 0L..(warmup + iterations) {
        var points: list<Point, 100000> = list {}
        parse_points(data, points)
        if points.count() > 0L {
            var x_sum = 0.0
            var y_sum = 0.0
            var z_sum = 0.0
            for point in points {
                x_sum += point.x
                y_sum += point.y
                z_sum += point.z
            }
            let count = (double)points.count()
            checksum = (checksum + checksum_double(x_sum / count)) % MODULUS
            checksum = (checksum + checksum_double(y_sum / count)) % MODULUS
            checksum = (checksum + checksum_double(z_sum / count)) % MODULUS
        }
    }
    print((checksum + checksum_data(data)) % MODULUS)
}
