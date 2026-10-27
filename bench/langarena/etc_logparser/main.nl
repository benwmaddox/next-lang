// Etc::LogParser: generate an access log, then count_value LangArena's 13 patterns in it.
// The patterns are matched by hand-written scanners that follow the regex semantics
// (leftmost, non-overlapping, alternatives in order) because next-lang has no regex library.
const TEST_LINES: long = 10L
const TEST_ITERATIONS: long = 2L
const RUN_LINES: long = 52000L
const RUN_ITERATIONS: long = 10L
const MODULUS: long = 4294967296L

type Log = Bytes max 12000000

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn method(k: long) -> Ascii max 8 {
    match k {
        0L => "GET"
        1L => "POST"
        2L => "PUT"
        _ => "DELETE"
    }
}

fn path(k: long) -> Ascii max 24 {
    match k {
        0L => "/index.html"
        1L => "/api/users"
        2L => "/admin"
        3L => "/images/logo.png"
        4L => "/etc/passwd"
        _ => "/wp-admin/setup.php"
    }
}

fn status(k: long) -> Ascii max 4 {
    match k {
        0L => "200"
        1L => "201"
        2L => "301"
        3L => "302"
        4L => "400"
        5L => "401"
        6L => "403"
        7L => "404"
        8L => "500"
        9L => "502"
        _ => "503"
    }
}

fn agent(k: long) -> Ascii max 16 {
    match k {
        0L => "Mozilla/5.0"
        1L => "Googlebot/2.1"
        2L => "curl/7.68.0"
        _ => "scanner/2.0"
    }
}

fn user(k: long) -> Ascii max 8 {
    match k {
        0L => "john"
        1L => "jane"
        2L => "alex"
        3L => "sarah"
        4L => "mike"
        5L => "anna"
        6L => "david"
        _ => "elena"
    }
}

fn domain(k: long) -> Ascii max 16 {
    match k {
        0L => "example.com"
        1L => "gmail.com"
        2L => "yahoo.com"
        3L => "hotmail.com"
        4L => "company.org"
        _ => "mail.ru"
    }
}

fn put(log: grow Bytes max 12000000, text: Ascii max 64) {
    log.try_append(text.bytes()).unwrap()
}

fn generate_line(log: grow Bytes max 12000000, i: long) {
    put(log, "192.168.1." + str(i % 255L + 1L))
    put(log, " - - [")
    put(log, str(i % 31L))
    put(log, "/Oct/2023:")
    put(log, str(i % 60L))
    put(log, ":55:36 +0000] \"")
    put(log, method(i % 4L))
    put(log, " ")
    if i % 3L == 0L {
        put(log, "/login?email=")
        put(log, user(i % 8L))
        put(log, str(i % 100L))
        put(log, "@")
        put(log, domain(i % 6L))
        put(log, "&password=secret")
        put(log, str(i % 10000L))
    } else if i % 5L == 0L {
        put(log, "/api/data?token=")
        for _t: long in 0L..(i % 3L + 1L) {
            put(log, "abcdef123456")
        }
    } else if i % 7L == 0L {
        put(log, "/user/profile?session_id=sess_")
        put(log, str_hex(i * 12345L))
    } else {
        put(log, path(i % 6L))
    }
    put(log, " HTTP/1.1\" ")
    put(log, status(i % 11L))
    put(log, " 2326 \"http://")
    put(log, domain(i % 6L))
    put(log, "\" \"")
    put(log, agent(i % 4L))
    put(log, "\"\n")
}

// ---- scanner helpers: every read is bounds-safe (-1 past the end) ----

fn at(log: Log, k: long) -> long {
    if k < log.len() { log[k].to_long() } else { -1L }
}

fn is_digit(c: long) -> bool { c >= 48L && c <= 57L }

fn is_letter(c: long) -> bool { (c >= 65L && c <= 90L) || (c >= 97L && c <= 122L) }

fn is_word(c: long) -> bool { is_letter(c) || is_digit(c) || c == 95L }

// [a-zA-Z0-9._%+-]
fn is_local(c: long) -> bool {
    is_letter(c) || is_digit(c) || c == 46L || c == 95L || c == 37L || c == 43L || c == 45L
}

// [a-zA-Z0-9.-]
fn is_domain(c: long) -> bool { is_letter(c) || is_digit(c) || c == 46L || c == 45L }

// [^&\s"]
fn is_value(c: long) -> bool {
    c >= 0L && c != 38L && c != 34L && c != 32L && !(c >= 9L && c <= 13L)
}

fn digits_end(log: Log, from: long) -> long {
    var j = from
    for _k: long in from..log.len() {
        if !is_digit(at(log, j)) { break }
        j += 1L
    }
    j
}

fn word_end(log: Log, from: long) -> long {
    var j = from
    for _k: long in from..log.len() {
        if !is_word(at(log, j)) { break }
        j += 1L
    }
    j
}

fn value_end(log: Log, from: long) -> long {
    var j = from
    for _k: long in from..log.len() {
        if !is_value(at(log, j)) { break }
        j += 1L
    }
    j
}

fn starts_with(log: Log, k: long, literal: Bytes max 16) -> bool {
    var same = true
    for j: long in 0L..literal.len() {
        if at(log, k + j) != literal[j].to_long() {
            same = false
            break
        }
    }
    same
}

// ---- the 13 patterns ----

// Literal alternatives separated by '|' (lowercase), matched in order at each position.
fn count_alternatives(log: Log, patterns: Bytes max 64, ignore_case: bool) -> long {
    var starts: long[8] = fill(0L)
    var lens: long[8] = fill(0L)
    var n = 0L
    var from = 0L
    let plen = patterns.len()
    for k: long in 0L..(plen + 1L) {
        if k == plen || patterns[k] == 124 {
            starts[n] = from
            lens[n] = k - from
            n += 1L
            from = k + 1L
        }
    }
    var count_value = 0L
    var next_free = 0L
    let size = log.len()
    for i: long in 0L..size {
        if i >= next_free {
            var hit = 0L
            for a: long in 0L..n {
                if hit == 0L && i + lens[a] <= size {
                    var same = true
                    for k: long in 0L..lens[a] {
                        var x = log[i + k].to_long()
                        if ignore_case && x >= 65L && x <= 90L { x += 32L }
                        if x != patterns[starts[a] + k].to_long() {
                            same = false
                            break
                        }
                    }
                    if same { hit = lens[a] }
                }
            }
            if hit > 0L {
                count_value += 1L
                next_free = i + hit
            }
        }
    }
    count_value
}

// " [5][0-9]{2} | [4][0-9]{2} "
fn count_errors(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 32L {
            let lead = at(log, i + 1L)
            if (lead == 53L || lead == 52L) && is_digit(at(log, i + 2L)) && is_digit(at(log, i + 3L)) && at(log, i + 4L) == 32L {
                count_value += 1L
                next_free = i + 5L
            }
        }
    }
    count_value
}

// \d+\.\d+\.\d+\.35
fn count_ips(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && is_digit(at(log, i)) {
            let e1 = digits_end(log, i)
            if at(log, e1) == 46L {
                let e2 = digits_end(log, e1 + 1L)
                if e2 > e1 + 1L && at(log, e2) == 46L {
                    let e3 = digits_end(log, e2 + 1L)
                    if e3 > e2 + 1L && at(log, e3) == 46L && at(log, e3 + 1L) == 51L && at(log, e3 + 2L) == 53L {
                        count_value += 1L
                        next_free = e3 + 3L
                    }
                }
            }
        }
    }
    count_value
}

// /api/[^ "]+
fn count_api_calls(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 47L && starts_with(log, i, b"/api/") {
            var j = i + 5L
            for _k: long in j..log.len() {
                let c = at(log, j)
                if c < 0L || c == 32L || c == 34L { break }
                j += 1L
            }
            if j > i + 5L {
                count_value += 1L
                next_free = j
            }
        }
    }
    count_value
}

// POST [^ ]* HTTP
fn count_post_requests(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 80L && starts_with(log, i, b"POST ") {
            var j = i + 5L
            for _k: long in j..log.len() {
                let c = at(log, j)
                if c < 0L || c == 32L { break }
                j += 1L
            }
            if at(log, j) == 32L && starts_with(log, j + 1L, b"HTTP") {
                count_value += 1L
                next_free = j + 5L
            }
        }
    }
    count_value
}

// literal followed by [^&\s"]+ ; returns the match end or -1
fn keyed_end(log: Log, k: long, literal: Bytes max 16) -> long {
    if starts_with(log, k, literal) {
        let from = k + literal.len()
        let e = value_end(log, from)
        if e > from { e } else { -1L }
    } else {
        -1L
    }
}

// name [_-]? tail [^&\s"]+  (name and tail are literals; the separator is optional)
fn keyed_optional_sep_end(log: Log, k: long, name: Bytes max 16, tail: Bytes max 16) -> long {
    if starts_with(log, k, name) {
        let j = k + name.len()
        let sep = at(log, j)
        var result = -1L
        if (sep == 95L || sep == 45L) && starts_with(log, j + 1L, tail) {
            let from = j + 1L + tail.len()
            let e = value_end(log, from)
            if e > from { result = e }
        }
        if result < 0L && starts_with(log, j, tail) {
            let from = j + tail.len()
            let e = value_end(log, from)
            if e > from { result = e }
        }
        result
    } else {
        -1L
    }
}

// password=[^&\s"]+
fn count_passwords(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 112L {
            let e = keyed_end(log, i, b"password=")
            if e > 0L {
                count_value += 1L
                next_free = e
            }
        }
    }
    count_value
}

// token=[^&\s"]+|api[_-]?key=[^&\s"]+
fn count_tokens(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free {
            var e = -1L
            let c = at(log, i)
            if c == 116L {
                e = keyed_end(log, i, b"token=")
            } else if c == 97L {
                e = keyed_optional_sep_end(log, i, b"api", b"key=")
            } else {}
            if e > 0L {
                count_value += 1L
                next_free = e
            }
        }
    }
    count_value
}

// session[_-]?id=[^&\s"]+
fn count_sessions(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 115L {
            let e = keyed_optional_sep_end(log, i, b"session", b"id=")
            if e > 0L {
                count_value += 1L
                next_free = e
            }
        }
    }
    count_value
}

// [a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}
fn count_emails(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && is_local(at(log, i)) {
            var r = i
            for _k: long in i..log.len() {
                if !is_local(at(log, r)) { break }
                r += 1L
            }
            // Every start inside this run reaches the same '@', so the run is tried once.
            next_free = r
            if at(log, r) == 64L {
                let d0 = r + 1L
                var de = d0
                for _k: long in d0..log.len() {
                    if !is_domain(at(log, de)) { break }
                    de += 1L
                }
                // backtrack from the end of the domain run to a '.' followed by 2+ letters
                var found = -1L
                for back: long in 0L..(de - d0) {
                    let p = de - 1L - back
                    if found < 0L && p > d0 && at(log, p) == 46L {
                        var le = p + 1L
                        for _k: long in le..log.len() {
                            if !is_letter(at(log, le)) { break }
                            le += 1L
                        }
                        if le - (p + 1L) >= 2L { found = le }
                    }
                }
                if found > 0L {
                    count_value += 1L
                    next_free = found
                }
            }
        }
    }
    count_value
}

// \[\d+/\w+/\d+:1[3-7]:\d+:\d+ [+\-]\d+\]
fn count_peak_hours(log: Log) -> long {
    var count_value = 0L
    var next_free = 0L
    for i: long in 0L..log.len() {
        if i >= next_free && at(log, i) == 91L {
            let e1 = digits_end(log, i + 1L)
            if e1 > i + 1L && at(log, e1) == 47L {
                let e2 = word_end(log, e1 + 1L)
                if e2 > e1 + 1L && at(log, e2) == 47L {
                    let e3 = digits_end(log, e2 + 1L)
                    let hour = at(log, e3 + 2L)
                    if e3 > e2 + 1L && at(log, e3) == 58L && at(log, e3 + 1L) == 49L && hour >= 51L && hour <= 55L && at(log, e3 + 3L) == 58L {
                        let e4 = digits_end(log, e3 + 4L)
                        if e4 > e3 + 4L && at(log, e4) == 58L {
                            let e5 = digits_end(log, e4 + 1L)
                            let sign = at(log, e5 + 1L)
                            if e5 > e4 + 1L && at(log, e5) == 32L && (sign == 43L || sign == 45L) {
                                let e6 = digits_end(log, e5 + 2L)
                                if e6 > e5 + 2L && at(log, e6) == 93L {
                                    count_value += 1L
                                    next_free = e6 + 1L
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    count_value
}

fn total_matches(log: Log) -> long {
    var total = 0L
    total += count_errors(log)
    total += count_alternatives(log, b"bot|crawler|scanner|spider|indexing|crawl|robot|spider", true)
    total += count_alternatives(log, b"etc/passwd|wp-admin|../", true)
    total += count_ips(log)
    total += count_api_calls(log)
    total += count_post_requests(log)
    total += count_alternatives(log, b"/login|/signin", true)
    total += count_alternatives(log, b"get|post|put", true)
    total += count_emails(log)
    total += count_passwords(log)
    total += count_tokens(log)
    total += count_sessions(log)
    total += count_peak_hours(log)
    total
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let lines = if run { RUN_LINES } else { TEST_LINES }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var log: Log = Bytes.empty()
    for i: long in 0L..lines {
        generate_line(log, i)
    }
    var checksum = 0L
    for _round: long in 0L..(warmup + iterations) {
        checksum = (checksum + total_matches(log)) % MODULUS
    }
    print(checksum)
}
