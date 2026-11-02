// A small grep: `cli_grep PATTERN` prints the lines of standard input that contain PATTERN, each prefixed with $NL_PREFIX when that is set.
// Exit status 0 when something matched, 1 when nothing did, 2 for a usage error.
const LINE_MAX: long = 4096L

fn contains(line: Bytes max LINE_MAX, pattern: Bytes max 256) -> bool {
    if pattern.count() == 0L { return true }
    if pattern.count() > line.count() { return false }
    for start in 0L..line.count() - pattern.count() + 1L {
        var same = true
        for offset in 0L..pattern.count() {
            if line[start + offset] != pattern[offset] { same = false; break }
        }
        if same { return true }
    }
    false
}

fn usage(env: Env) -> never {
    match env.err.write(b"usage: cli_grep PATTERN < input\n") { ok(_) => env.exit(2), err(_) => env.exit(2) }
}

fn main(env: Env) {
    let arguments = env.args()
    if arguments.count() != 1L { usage(env) }
    var pattern: Bytes max 256 = Bytes.empty()
    let first = match arguments.get(0L) { some(value) => value, none => usage(env) }
    for index in 0L..first.count() {
        match first.get(index) {
            some(value) => { discard pattern.push(value) },
            none => (),
        }
    }
    var prefix: Bytes max 32 = Bytes.empty()
    if env.getenv("NL_PREFIX", prefix) < 0L { prefix = Bytes.empty() }

    var chunk: Bytes max 4096 = Bytes.empty()
    var line: Bytes max LINE_MAX = Bytes.empty()
    var matched = 0L
    var done = false
    while !done {
        let got = env.stdin_read(chunk)
        var pending = got > 0L
        var end_of_input = got <= 0L
        for index in 0L..chunk.count() {
            if !pending { break }
            let c = chunk[index]
            if c == 10 {
                if contains(line, pattern) {
                    matched += 1L
                    var out: Bytes max 5000 = Bytes.empty()
                    discard out.try_append($"{prefix}{line}\n")
                    match env.out.write(out) { ok(_) => (), err(_) => env.exit(3) }
                }
                line = Bytes.empty()
            } else {
                discard line.push(c)
            }
        }
        if end_of_input {
            if line.count() > 0L && contains(line, pattern) {
                matched += 1L
                var out: Bytes max 5000 = Bytes.empty()
                discard out.try_append($"{prefix}{line}\n")
                match env.out.write(out) { ok(_) => (), err(_) => env.exit(3) }
            }
            done = true
        }
    }
    env.exit(if matched > 0L { 0 } else { 1 })
}
