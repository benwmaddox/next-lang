// The service compiler: `svc <package-dir>` turns the package's *.svc files into next-lang code in services.gen.nl.
// Same input and output as the Python prototype it replaces (tools/svc.py); the service language is described there.
// Everything has a fixed capacity, chosen below; a package that does not fit says so.

type Name = Bytes max 192
type Buf = list<byte, 524288>

struct Pair {
    name: Name = Bytes.empty()
    text: Name = Bytes.empty()
}

struct StateItem {
    name: Name = Bytes.empty()
    ty: Name = Bytes.empty()
    init: Name = Bytes.empty()
}

struct Handler {
    name: Name = Bytes.empty()
    params: list<Pair, 8> = list {}
    reply: Name = Bytes.empty()
    body_start: long = 0L
    body_len: long = 0L
    line: long = 0L
}

struct Service {
    name: Name = Bytes.empty()
    path: Name = Bytes.empty()
    line: long = 0L
    config: list<Pair, 16> = list {}
    state: list<StateItem, 32> = list {}
    mailbox: long = 64L
    init_start: long = 0L
    init_len: long = 0L
    tick_ms: long = 0L
    tick_start: long = 0L
    tick_len: long = 0L
    tick_line: long = 0L
    idle_start: long = 0L
    idle_len: long = 0L
    idle_line: long = 0L
    handlers: list<Handler, 16> = list {}
}

struct Entry {
    name: Name = Bytes.empty()
}

struct Gen {
    services: list<Service, 16> = list {}
    edges: list<Entry, 256> = list {}
    all: Buf = list {}
    out: Buf = list {}
    scratch: Buf = list {}
}

// the result of matching a block header line
struct Header {
    kind: long = 0L
    ms: long = 0L
    name: Name = Bytes.empty()
    params_from: long = 0L
    params_to: long = 0L
    reply: Name = Bytes.empty()
}

// ---------------------------------------------------------------- errors and small helpers

fn ew(env: Env, text: Ascii max 1024) {
    match env.err.write(text.bytes()) { ok(_) => (), err(_) => env.exit(3) }
}

fn ew_name(env: Env, text: Name) {
    match env.err.write(text) { ok(_) => (), err(_) => env.exit(3) }
}

fn ew_num(env: Env, value: long) {
    match env.err.write(str(value).bytes()) { ok(_) => (), err(_) => env.exit(3) }
}

fn start_error(env: Env, path: Name, line: long) {
    ew(env, "nlc: service error: ")
    ew_name(env, path)
    ew(env, ":")
    ew_num(env, line)
    ew(env, ": ")
}

fn end_error(env: Env) -> never {
    ew(env, "\n")
    env.exit(1)
}

fn limit_error(env: Env, what: Ascii max 128) -> never {
    ew(env, "nlc: service error: the generator's capacity for ")
    ew(env, what)
    ew(env, " is exceeded\n")
    env.exit(1)
}

fn put(out: write Buf, text: Ascii max 1024) {
    for index in 0L..text.len() { discard out.push(text[index]) }
}

fn put_name(out: write Buf, text: Name) {
    for index in 0L..text.count() { discard out.push(text[index]) }
}

fn put_num(out: write Buf, value: long) {
    let digits = str(value)
    for index in 0L..digits.len() { discard out.push(digits[index]) }
}

fn put_range(out: write Buf, source: Buf, start: long, length: long) {
    for index in start..start + length { discard out.push(source[index]) }
}

fn is_space(c: long) -> bool { c == 32L || (c >= 9L && c <= 13L) }
fn is_digit(c: long) -> bool { c >= 48L && c <= 57L }
fn is_alpha(c: long) -> bool { (c >= 65L && c <= 90L) || (c >= 97L && c <= 122L) }
fn is_word(c: long) -> bool { is_alpha(c) || is_digit(c) || c == 95L }

fn names_equal(a: Name, b: Name) -> bool {
    if a.count() != b.count() { return false }
    for index in 0L..a.count() {
        if a[index] != b[index] { return false }
    }
    true
}

fn name_is(name: Name, text: Ascii max 64) -> bool {
    if name.count() != text.len() { return false }
    for index in 0L..text.len() {
        if name[index] != text[index] { return false }
    }
    true
}

fn starts_with_at(buffer: Buf, at: long, end: long, text: Ascii max 64) -> bool {
    if at + text.len() > end { return false }
    for index in 0L..text.len() {
        if buffer[at + index] != text[index] { return false }
    }
    true
}

// "GetAll" -> "get_all"
fn snake(name: Name) -> Name {
    var out: Name = Bytes.empty()
    for index in 0L..name.count() {
        let c = name[index].to_long()
        if c >= 65L && c <= 90L {
            if index > 0L { discard out.push((byte)95) }
            discard out.push((byte)(c + 32L))
        } else {
            discard out.push(name[index])
        }
    }
    out
}

fn range_name(source: Buf, from: long, to: long) -> Name {
    var a = from
    var b = to
    while a < b && is_space(source[a].to_long()) { a += 1L }
    while b > a && is_space(source[b - 1L].to_long()) { b -= 1L }
    var out: Name = Bytes.empty()
    for index in a..b { discard out.push(source[index]) }
    out
}

// ---------------------------------------------------------------- reading a .svc file

fn skip_ws(source: Buf, at: long, end: long) -> long {
    var index = at
    while index < end && is_space(source[index].to_long()) { index += 1L }
    index
}

fn skip_word(source: Buf, at: long, end: long) -> long {
    var index = at
    while index < end && is_word(source[index].to_long()) { index += 1L }
    index
}

// `keyword\s+(\w+)`: the end of the word and where it starts, or -1.
fn keyword_word(source: Buf, ls: long, le: long, keyword: Ascii max 16, word_start: write long) -> long {
    if !starts_with_at(source, ls, le, keyword) { return -1L }
    let after = ls + keyword.len()
    let at = skip_ws(source, after, le)
    if at == after { return -1L }
    let end = skip_word(source, at, le)
    if end == at { return -1L }
    word_start = at
    end
}

// A block header: init, idle, tick every N ms|s, or on Name(params) [-> Reply], then `{` at the end of the line.
fn match_header(source: Buf, ls: long, le: long) -> Header {
    var h = Header {}
    var e = le
    while e > ls && is_space(source[e - 1L].to_long()) { e -= 1L }
    if e == ls || source[e - 1L] != 123 { return h }
    let content_end = e - 1L
    if starts_with_at(source, ls, content_end, "init") {
        if skip_ws(source, ls + 4L, content_end) == content_end { h.kind = 1L; return h }
    }
    if starts_with_at(source, ls, content_end, "idle") {
        if skip_ws(source, ls + 4L, content_end) == content_end { h.kind = 2L; return h }
    }
    if starts_with_at(source, ls, content_end, "tick") {
        var at = skip_ws(source, ls + 4L, content_end)
        if at > ls + 4L && starts_with_at(source, at, content_end, "every") {
            let after_every = at + 5L
            at = skip_ws(source, after_every, content_end)
            if at > after_every {
                var number = 0L
                let digits_start = at
                while at < content_end && is_digit(source[at].to_long()) {
                    number = number * 10L + (source[at].to_long() - 48L)
                    at += 1L
                }
                if at > digits_start {
                    at = skip_ws(source, at, content_end)
                    var unit = 0L
                    if starts_with_at(source, at, content_end, "ms") { unit = 1L; at += 2L } else if starts_with_at(source, at, content_end, "s") { unit = 1000L; at += 1L }
                    if unit != 0L && skip_ws(source, at, content_end) == content_end {
                        h.kind = 3L
                        h.ms = number * unit
                        return h
                    }
                }
            }
        }
    }
    if starts_with_at(source, ls, content_end, "on") {
        var word_start = 0L
        let name_end = keyword_word(source, ls, content_end, "on", word_start)
        if name_end > 0L {
            let paren = skip_ws(source, name_end, content_end)
            if paren < content_end && source[paren] == 40 {
                // the rightmost ')' after which only `-> Reply` or spaces remain
                var q = content_end
                while q > paren + 1L {
                    q -= 1L
                    if source[q] == 41 {
                        let rest = skip_ws(source, q + 1L, content_end)
                        if rest == content_end {
                            h.kind = 4L
                            h.name = range_name(source, word_start, name_end)
                            h.params_from = paren + 1L
                            h.params_to = q
                            return h
                        }
                        if starts_with_at(source, rest, content_end, "->") {
                            let reply = range_name(source, rest + 2L, content_end)
                            if content_end > rest + 2L {
                                h.kind = 4L
                                h.name = range_name(source, word_start, name_end)
                                h.params_from = paren + 1L
                                h.params_to = q
                                h.reply = reply
                                return h
                            }
                        }
                    }
                }
            }
        }
    }
    h
}

// Splits at commas outside <> and (), each part as `name: type` (an item with no colon has an empty type).
fn split_params(env: Env, source: Buf, from: long, to: long, out: write list<Pair, 8>) {
    var depth = 0L
    var item_start = from
    for index in from..to + 1L {
        let at_end = index == to
        let c = if at_end { 0L } else { source[index].to_long() }
        if c == 60L || c == 40L { depth += 1L } else if c == 62L || c == 41L { depth -= 1L }
        if at_end || (c == 44L && depth == 0L) {
            var blank = true
            for k in item_start..index { if !is_space(source[k].to_long()) { blank = false } }
            if !(at_end && blank) {
                var colon = index
                for k in item_start..index { if colon == index && source[k] == 58 { colon = k } }
                let name = range_name(source, item_start, colon)
                var type_text: Name = Bytes.empty()
                if colon < index { type_text = range_name(source, colon + 1L, index) }
                match out.push(Pair { name, text: type_text }) { ok(_) => (), err(_) => limit_error(env, "handler parameters") }
            }
            item_start = index + 1L
        }
    }
}

// Reads the services of the file whose text is g.all[base, end), with `path` for error messages.
fn read_services(env: Env, g: write Gen, path: Name, base: long, end: long) {
    var current = -1L
    var line_start = base
    var number = 1L
    while line_start <= end {
        var line_end = line_start
        while line_end < end && g.all[line_end] != 10 { line_end += 1L }
        var next_start = line_end + 1L
        var next_number = number + 1L
        var blank = true
        for k in line_start..line_end { if !is_space(g.all[k].to_long()) { blank = false } }
        let comment = line_end - line_start >= 2L && g.all[line_start] == 47 && g.all[line_start + 1L] == 47
        if !blank && !comment {
            var word_start = 0L
            // service Name
            let service_end = keyword_word(g.all, line_start, line_end, "service", word_start)
            if service_end > 0L && skip_ws(g.all, service_end, line_end) == line_end {
                var service = Service { path, line: number }
                service.name = range_name(g.all, word_start, service_end)
                match g.services.push(service) { ok(_) => (), err(_) => limit_error(env, "services") }
                current = g.services.count() - 1L
            } else if current < 0L {
                start_error(env, path, number)
                ew(env, "expected `service Name`")
                end_error(env)
            } else {
                let config_end = keyword_word(g.all, line_start, line_end, "config", word_start)
                let colon = if config_end > 0L { skip_ws(g.all, config_end, line_end) } else { -1L }
                if config_end > 0L && colon < line_end && g.all[colon] == 58 && line_end > colon + 1L {
                    let pair = Pair { name: range_name(g.all, word_start, config_end), text: range_name(g.all, colon + 1L, line_end) }
                    match g.services[current].config.push(pair) { ok(_) => (), err(_) => limit_error(env, "config fields") }
                } else {
                    let state_end = keyword_word(g.all, line_start, line_end, "state", word_start)
                    var state_ok = false
                    if state_end > 0L {
                        let state_colon = skip_ws(g.all, state_end, line_end)
                        if state_colon < line_end && g.all[state_colon] == 58 {
                            let type_start = skip_ws(g.all, state_colon + 1L, line_end)
                            // the first '=' with at least one character of type before it and something after it
                            var equals = -1L
                            if type_start + 1L < line_end {
                                for k in type_start + 1L..line_end { if equals < 0L && g.all[k] == 61 { equals = k } }
                            }
                            if equals > 0L && line_end > equals + 1L {
                                let item = StateItem {
                                    name: range_name(g.all, word_start, state_end),
                                    ty: range_name(g.all, type_start, equals),
                                    init: range_name(g.all, equals + 1L, line_end),
                                }
                                match g.services[current].state.push(item) { ok(_) => (), err(_) => limit_error(env, "state fields") }
                                state_ok = true
                            }
                        }
                    }
                    var mailbox_ok = false
                    if !state_ok {
                        // `mailbox\s+(\d+)\s*`
                        let after = line_start + 7L
                        if starts_with_at(g.all, line_start, line_end, "mailbox") {
                            let digits = skip_ws(g.all, after, line_end)
                            if digits > after {
                                var value = 0L
                                var at = digits
                                while at < line_end && is_digit(g.all[at].to_long()) {
                                    value = value * 10L + (g.all[at].to_long() - 48L)
                                    at += 1L
                                }
                                if at > digits && skip_ws(g.all, at, line_end) == line_end {
                                    g.services[current].mailbox = value
                                    mailbox_ok = true
                                }
                            }
                        }
                    }
                    if !state_ok && !mailbox_ok {
                        let header = match_header(g.all, line_start, line_end)
                        if header.kind == 0L {
                            start_error(env, path, number)
                            ew(env, "unexpected `")
                            ew_name(env, range_name(g.all, line_start, line_end))
                            ew(env, "`")
                            end_error(env)
                        }
                        // the block runs to a line that is exactly `}`
                        let body_start = line_end + 1L
                        var scan = body_start
                        var scan_number = number + 1L
                        var close_start = -1L
                        while scan <= end && close_start < 0L {
                            var scan_end = scan
                            while scan_end < end && g.all[scan_end] != 10 { scan_end += 1L }
                            if scan_end == scan + 1L && g.all[scan] == 125 && scan < end {
                                close_start = scan
                            } else {
                                scan = scan_end + 1L
                                scan_number += 1L
                            }
                        }
                        if close_start < 0L {
                            start_error(env, path, number)
                            ew(env, "this block is not closed by a `}` at the start of a line")
                            end_error(env)
                        }
                        var body_len = close_start - 1L - body_start
                        if body_len < 0L { body_len = 0L }
                        if close_start == body_start { body_len = 0L }
                        next_start = close_start + 2L
                        next_number = scan_number + 1L
                        if header.kind == 1L {
                            g.services[current].init_start = body_start
                            g.services[current].init_len = body_len
                        } else if header.kind == 2L {
                            g.services[current].idle_start = body_start
                            g.services[current].idle_len = body_len
                            g.services[current].idle_line = number
                        } else if header.kind == 3L {
                            g.services[current].tick_ms = header.ms
                            g.services[current].tick_start = body_start
                            g.services[current].tick_len = body_len
                            g.services[current].tick_line = number
                        } else {
                            var handler = Handler { name: header.name, reply: header.reply, body_start, body_len, line: number }
                            var params: list<Pair, 8> = list {}
                            split_params(env, g.all, header.params_from, header.params_to, params)
                            handler.params = params
                            match g.services[current].handlers.push(handler) { ok(_) => (), err(_) => limit_error(env, "handlers") }
                        }
                    }
                }
            }
        }
        line_start = next_start
        number = next_number
    }
}

// ---------------------------------------------------------------- the checks over the whole package

// Whether the comment-free text in g.scratch has `name` at a word boundary followed by: 0: spaces and '(';
// 1: spaces and ',' or ')'; 2: a word boundary.
fn has_call(g: Gen, name: Name, mode: long) -> bool {
    let n = g.scratch.count()
    var start = 0L
    while start + name.count() <= n {
        var matches = start == 0L || !is_word(g.scratch[start - 1L].to_long())
        if matches {
            for k in 0L..name.count() {
                if g.scratch[start + k] != name[k] { matches = false }
            }
        }
        if matches {
            var at = start + name.count()
            if mode == 2L {
                if at >= n || !is_word(g.scratch[at].to_long()) { return true }
            } else {
                while at < n && is_space(g.scratch[at].to_long()) { at += 1L }
                if at < n {
                    let c = g.scratch[at]
                    if mode == 0L && c == 40 { return true }
                    if mode == 1L && (c == 44 || c == 41) { return true }
                }
            }
        }
        start += 1L
    }
    false
}

// The body at g.all[start, start+length) with // comments removed, into g.scratch.
fn strip_comments(g: write Gen, start: long, length: long) {
    g.scratch = list {}
    var in_comment = false
    for index in start..start + length {
        let c = g.all[index]
        if in_comment {
            if c == 10 {
                in_comment = false
                discard g.scratch.push(c)
            }
        } else if c == 47 && index + 1L < start + length && g.all[index + 1L] == 47 {
            in_comment = true
        } else {
            discard g.scratch.push(c)
        }
    }
}

fn function_name(service: Name, handler: Name) -> Name {
    var out: Name = Bytes.empty()
    discard out.try_append(service)
    discard out.push((byte)95)
    discard out.try_append(snake(handler))
    out
}

// The last service with this name (a later definition replaces an earlier one), or -1.
fn find_service(g: Gen, name: Name) -> long {
    var found = -1L
    for index in 0L..g.services.count() {
        if names_equal(g.services[index].name, name) { found = index }
    }
    found
}

fn add_edge(env: Env, g: write Gen, source: Name, handler: Name, target: Name, function: Name) {
    var line: Name = Bytes.empty()
    discard line.try_append(source)
    discard line.try_append(".".bytes())
    discard line.try_append(handler)
    discard line.try_append(" -> ".bytes())
    discard line.try_append(target)
    discard line.try_append(" (".bytes())
    discard line.try_append(function)
    discard line.try_append(")".bytes())
    match g.edges.push(Entry { name: line }) { ok(_) => (), err(_) => limit_error(env, "message edges") }
}

fn wait_error(env: Env, path: Name, line: long, service: Name, handler: Name, function: Name) -> never {
    start_error(env, path, line)
    ew(env, "handler ")
    ew_name(env, service)
    ew(env, ".")
    ew_name(env, handler)
    ew(env, " calls ")
    ew_name(env, function)
    ew(env, " and would wait for the answer; a service handler never waits. Pass `reply` (or a sender) on to the other service instead")
    end_error(env)
}

// One body (a handler, the tick or the idle step) of `service`: no waiting calls, replies answered.
fn check_body(env: Env, g: write Gen, index: long, handler_name: Name, reply: Name, start: long, length: long, line: long) {
    let service = g.services[index]
    strip_comments(g, start, length)
    var receivers_names: list<Entry, 17> = list {}
    var receivers_targets: list<Entry, 17> = list {}
    var me: Name = Bytes.empty()
    discard me.try_append("me".bytes())
    match receivers_names.push(Entry { name: me }) { ok(_) => (), err(_) => () }
    match receivers_targets.push(Entry { name: service.name }) { ok(_) => (), err(_) => () }
    for field in service.config {
        if find_service(g, field.text) >= 0L {
            var receiver: Name = Bytes.empty()
            discard receiver.try_append("config.".bytes())
            discard receiver.try_append(field.name)
            match receivers_names.push(Entry { name: receiver }) { ok(_) => (), err(_) => () }
            match receivers_targets.push(Entry { name: field.text }) { ok(_) => (), err(_) => () }
        }
    }
    for r in 0L..receivers_names.count() {
        let target_name = receivers_targets[r].name
        let target = g.services[find_service(g, target_name)]
        for target_handler in target.handlers {
            var pattern: Name = Bytes.empty()
            discard pattern.try_append(receivers_names[r].name)
            discard pattern.push((byte)46)
            discard pattern.try_append(snake(target_handler.name))
            let function = function_name(target_name, target_handler.name)
            if has_call(g, pattern, 0L) {
                if target_handler.reply.count() > 0L {
                    wait_error(env, service.path, line, service.name, handler_name, function)
                }
                add_edge(env, g, service.name, handler_name, target_name, function)
            }
        }
    }
    // calls of the sender functions (Cache_get(...)) by name
    for other_index in 0L..g.services.count() {
        if find_service(g, g.services[other_index].name) == other_index {
            for target_handler in g.services[other_index].handlers {
                let function = function_name(g.services[other_index].name, target_handler.name)
                if target_handler.reply.count() > 0L && has_call(g, function, 0L) {
                    wait_error(env, service.path, line, service.name, handler_name, function)
                }
            }
        }
    }
    for other_index in 0L..g.services.count() {
        if find_service(g, g.services[other_index].name) == other_index {
            let other = g.services[other_index]
            for target_handler in other.handlers {
                let function = function_name(other.name, target_handler.name)
                if target_handler.reply.count() == 0L && has_call(g, function, 0L) {
                    add_edge(env, g, service.name, handler_name, other.name, function)
                }
            }
            for target_handler in other.handlers {
                let function = function_name(other.name, target_handler.name)
                if target_handler.reply.count() > 0L && has_call(g, function, 0L) {
                    add_edge(env, g, service.name, handler_name, other.name, function)
                }
            }
        }
    }
    var reply_word: Name = Bytes.empty()
    discard reply_word.try_append("reply".bytes())
    if reply.count() > 0L {
        if !has_call(g, reply_word, 0L) && !has_call(g, reply_word, 1L) {
            start_error(env, service.path, line)
            ew(env, "handler ")
            ew_name(env, service.name)
            ew(env, ".")
            ew_name(env, handler_name)
            ew(env, " declares a reply (-> ")
            ew_name(env, reply)
            ew(env, ") but never answers: call reply(value), or pass `reply` on to another service")
            end_error(env)
        }
    } else if has_call(g, reply_word, 2L) {
        start_error(env, service.path, line)
        ew(env, "handler ")
        ew_name(env, service.name)
        ew(env, ".")
        ew_name(env, handler_name)
        ew(env, " uses `reply` but declares none; add `-> Type`")
        end_error(env)
    }
}

fn check_services(env: Env, g: write Gen) {
    for index in 0L..g.services.count() {
        let service = g.services[index]
        for handler in service.handlers {
            check_body(env, g, index, handler.name, handler.reply, handler.body_start, handler.body_len, handler.line)
        }
        var tick: Name = Bytes.empty()
        discard tick.try_append("tick".bytes())
        if service.tick_ms > 0L {
            check_body(env, g, index, tick, Bytes.empty(), service.tick_start, service.tick_len, service.tick_line)
        }
        if service.idle_len > 0L {
            check_body(env, g, index, tick, Bytes.empty(), service.idle_start, service.idle_len, service.idle_line)
        }
    }
}

// ---------------------------------------------------------------- the code written

fn sep(g: write Gen) {
    if g.out.count() > 0L { put(g.out, "\n") }
}

// `n: t` pairs joined by ", " (after an optional first, already written, part)
fn put_pairs(out: write Buf, pairs: list<Pair, 8>, leading: bool) {
    var first = !leading
    for pair in pairs {
        if !first { put(out, ", ") }
        first = false
        put_name(out, pair.name)
        put(out, ": ")
        put_name(out, pair.text)
    }
}

// The body with `reply(` made a call of the service's answer function.
fn put_reply_body(out: write Buf, source: Buf, start: long, length: long, service: Name, handler: Name) {
    var index = start
    let end = start + length
    while index < end {
        if index + 6L <= end && source[index] == 114 && source[index + 1L] == 101 && source[index + 2L] == 112 && source[index + 3L] == 108 &&
            source[index + 4L] == 121 && source[index + 5L] == 40 && (index == start || !is_word(source[index - 1L].to_long())) {
            put_name(out, service)
            put(out, "_answer_")
            put_name(out, snake(handler))
            put(out, "(reply, ")
            index += 6L
        } else {
            discard out.push(source[index])
            index += 1L
        }
    }
}

fn has_config(service: Service, name: Ascii max 16, ty: Ascii max 16) -> bool {
    for pair in service.config {
        if name_is(pair.name, name) && name_is(pair.text, ty) { return true }
    }
    false
}

// One arm of the dispatch: `Message.Handler(args) => { Service_on_handler(state, config, me, args.a) },`.
fn put_arm(g: write Gen, service: Service, handler: Handler, pad: Ascii max 64) {
    let has_fields = handler.params.count() > 0L || handler.reply.count() > 0L
    put(g.out, pad)
    put(g.out, "    ")
    put_name(g.out, service.name)
    put(g.out, "Message.")
    put_name(g.out, handler.name)
    if has_fields { put(g.out, "(args)") }
    put(g.out, " => { ")
    put_name(g.out, service.name)
    put(g.out, "_on_")
    put_name(g.out, snake(handler.name))
    put(g.out, "(state, config, me")
    for pair in handler.params {
        put(g.out, ", args.")
        put_name(g.out, pair.name)
    }
    if handler.reply.count() > 0L { put(g.out, ", args.reply") }
    put(g.out, ") },\n")
}

fn put_dispatch(g: write Gen, service: Service, pad: Ascii max 64, subject: Ascii max 16) {
    put(g.out, pad)
    put(g.out, "match ")
    put(g.out, subject)
    put(g.out, " {\n")
    for handler in service.handlers { put_arm(g, service, handler, pad) }
    put(g.out, pad)
    put(g.out, "    ")
    put_name(g.out, service.name)
    put(g.out, "Message.Stop => { break },\n")
    put(g.out, pad)
    put(g.out, "}")
}

fn generate(env: Env, g: write Gen, index: long) {
    let service = g.services[index]
    let name = service.name
    if service.handlers.count() == 0L {
        start_error(env, service.path, service.line)
        ew(env, "service ")
        ew_name(env, name)
        ew(env, " has no `on` handler")
        end_error(env)
    }
    if service.tick_ms > 0L && !has_config(service, "env", "Env") {
        start_error(env, service.path, service.tick_line)
        ew(env, "a service with `tick` needs `config env: Env` (the clock)")
        end_error(env)
    }
    for i in 0L..service.handlers.count() {
        for j in 0L..i {
            if names_equal(service.handlers[i].name, service.handlers[j].name) || name_is(service.handlers[i].name, "Stop") {
                start_error(env, service.path, service.handlers[i].line)
                ew(env, "handler ")
                ew_name(env, service.handlers[i].name)
                ew(env, " is defined twice or is the reserved Stop")
                end_error(env)
            }
        }
        if i == 0L && name_is(service.handlers[0].name, "Stop") {
            start_error(env, service.path, service.handlers[0].line)
            ew(env, "handler Stop is defined twice or is the reserved Stop")
            end_error(env)
        }
    }
    sep(g)
    put(g.out, "// service ")
    put_name(g.out, name)
    put(g.out, " (generated from its .svc file)")
    sep(g)
    put(g.out, "struct ")
    put_name(g.out, name)
    put(g.out, " {\n    inbox: Sender<")
    put_name(g.out, name)
    put(g.out, "Message>\n}\n")
    sep(g)
    put(g.out, "struct ")
    put_name(g.out, name)
    put(g.out, "State {\n")
    if service.state.count() > 0L {
        var first = true
        for item in service.state {
            if !first { put(g.out, "\n") }
            first = false
            put(g.out, "    ")
            put_name(g.out, item.name)
            put(g.out, ": ")
            put_name(g.out, item.ty)
        }
        put(g.out, "\n}\n")
    } else {
        put(g.out, "    unused: long\n}\n")
    }
    sep(g)
    put(g.out, "struct ")
    put_name(g.out, name)
    put(g.out, "Config {\n")
    if service.config.count() > 0L {
        var first = true
        for pair in service.config {
            if !first { put(g.out, "\n") }
            first = false
            put(g.out, "    ")
            put_name(g.out, pair.name)
            put(g.out, ": ")
            put_name(g.out, pair.text)
        }
        put(g.out, "\n}\n")
    } else {
        put(g.out, "    unused: long\n}\n")
    }
    // the argument structs, then the message enum
    for handler in service.handlers {
        let has_fields = handler.params.count() > 0L || handler.reply.count() > 0L
        if has_fields {
            sep(g)
            put(g.out, "struct ")
            put_name(g.out, name)
            put_name(g.out, handler.name)
            put(g.out, "Args {\n")
            var first = true
            for pair in handler.params {
                if !first { put(g.out, "\n") }
                first = false
                put(g.out, "    ")
                put_name(g.out, pair.name)
                put(g.out, ": ")
                put_name(g.out, pair.text)
            }
            if handler.reply.count() > 0L {
                if !first { put(g.out, "\n") }
                put(g.out, "    reply: Sender<")
                put_name(g.out, handler.reply)
                put(g.out, ">")
            }
            put(g.out, "\n}\n")
        }
    }
    sep(g)
    put(g.out, "enum ")
    put_name(g.out, name)
    put(g.out, "Message {\n")
    for handler in service.handlers {
        put(g.out, "    ")
        put_name(g.out, handler.name)
        if handler.params.count() > 0L || handler.reply.count() > 0L {
            put(g.out, "(")
            put_name(g.out, name)
            put_name(g.out, handler.name)
            put(g.out, "Args)")
        }
        put(g.out, ",\n")
    }
    put(g.out, "    Stop,\n}\n")
    // the handlers
    for handler in service.handlers {
        if handler.reply.count() > 0L {
            sep(g)
            put(g.out, "fn ")
            put_name(g.out, name)
            put(g.out, "_answer_")
            put_name(g.out, snake(handler.name))
            put(g.out, "(to: Sender<")
            put_name(g.out, handler.reply)
            put(g.out, ">, value: ")
            put_name(g.out, handler.reply)
            put(g.out, ") {\n    match to.send(value) {\n        ok(_) => {},\n        err(_) => {},\n    }\n}\n")
        }
        sep(g)
        put(g.out, "fn ")
        put_name(g.out, name)
        put(g.out, "_on_")
        put_name(g.out, snake(handler.name))
        put(g.out, "(state: write ")
        put_name(g.out, name)
        put(g.out, "State, config: ")
        put_name(g.out, name)
        put(g.out, "Config, me: ")
        put_name(g.out, name)
        for pair in handler.params {
            put(g.out, ", ")
            put_name(g.out, pair.name)
            put(g.out, ": ")
            put_name(g.out, pair.text)
        }
        if handler.reply.count() > 0L {
            put(g.out, ", reply: Sender<")
            put_name(g.out, handler.reply)
            put(g.out, ">")
        }
        put(g.out, ") {\n")
        if handler.reply.count() > 0L {
            put_reply_body(g.out, g.all, handler.body_start, handler.body_len, name, handler.name)
        } else {
            put_range(g.out, g.all, handler.body_start, handler.body_len)
        }
        put(g.out, "\n}\n")
    }
    if service.tick_ms > 0L {
        sep(g)
        put(g.out, "fn ")
        put_name(g.out, name)
        put(g.out, "_on_tick(state: write ")
        put_name(g.out, name)
        put(g.out, "State, config: ")
        put_name(g.out, name)
        put(g.out, "Config, me: ")
        put_name(g.out, name)
        put(g.out, ", missed: long) {\n")
        put_range(g.out, g.all, service.tick_start, service.tick_len)
        put(g.out, "\n}\n")
    }
    if service.idle_len > 0L {
        sep(g)
        put(g.out, "// runs when the mailbox is empty; returns true when it has more to do\nfn ")
        put_name(g.out, name)
        put(g.out, "_on_idle(state: write ")
        put_name(g.out, name)
        put(g.out, "State, config: ")
        put_name(g.out, name)
        put(g.out, "Config, me: ")
        put_name(g.out, name)
        put(g.out, ") -> bool {\n")
        put_range(g.out, g.all, service.idle_start, service.idle_len)
        put(g.out, "\n}\n")
    }
    // the run loop
    sep(g)
    put(g.out, "fn ")
    put_name(g.out, name)
    put(g.out, "_run(inbox: Receiver<")
    put_name(g.out, name)
    put(g.out, "Message>, self_inbox: Sender<")
    put_name(g.out, name)
    put(g.out, "Message>")
    for pair in service.config {
        put(g.out, ", ")
        put_name(g.out, pair.name)
        put(g.out, ": ")
        put_name(g.out, pair.text)
    }
    put(g.out, ") {\n    var state = ")
    put_name(g.out, name)
    put(g.out, "State { ")
    if service.state.count() > 0L {
        var first = true
        for item in service.state {
            if !first { put(g.out, ", ") }
            first = false
            put_name(g.out, item.name)
            put(g.out, ": ")
            put_name(g.out, item.init)
        }
    } else {
        put(g.out, "unused: 0L")
    }
    put(g.out, " }\n    let config = ")
    put_name(g.out, name)
    put(g.out, "Config { ")
    if service.config.count() > 0L {
        var first = true
        for pair in service.config {
            if !first { put(g.out, ", ") }
            first = false
            put_name(g.out, pair.name)
            put(g.out, ": ")
            put_name(g.out, pair.name)
        }
    } else {
        put(g.out, "unused: 0L")
    }
    put(g.out, " }\n    let me = ")
    put_name(g.out, name)
    put(g.out, " { inbox: self_inbox }\n")
    if service.init_len > 0L {
        put(g.out, "    // init\n")
        put_range(g.out, g.all, service.init_start, service.init_len)
        put(g.out, "\n")
    }
    if service.tick_ms > 0L {
        put(g.out, "    var next_tick = config.env.now_ms() + ")
        put_num(g.out, service.tick_ms)
        put(g.out, "L\n")
    }
    put(g.out, "    while true {\n")
    var pad: Ascii max 32 = "        "
    if service.idle_len > 0L {
        put(g.out, "        var busy = false\n        match inbox.recv() {\n            some(message) => {\n                busy = true\n")
        put_dispatch(g, service, "                ", "message")
        put(g.out, "\n            },\n            none => {\n                if inbox.is_closed() { break }\n                busy = ")
        put_name(g.out, name)
        put(g.out, "_on_idle(state, config, me)\n            },\n        }\n        if !busy {\n")
        pad = "            "
    }
    if service.tick_ms > 0L {
        put(g.out, pad)
        put(g.out, "var wait = next_tick - config.env.now_ms()\n")
        put(g.out, pad)
        put(g.out, "if wait < 0L { wait = 0L }\n")
        put(g.out, pad)
        put(g.out, "match inbox.recv_for(wait) {\n")
    } else {
        put(g.out, pad)
        put(g.out, "match inbox.recv_wait() {\n")
    }
    put(g.out, pad)
    put(g.out, "    some(message) => {\n")
    var deeper: Ascii max 32 = "                "
    if service.idle_len > 0L { deeper = "                    " }
    put_dispatch(g, service, deeper, "message")
    put(g.out, "\n")
    put(g.out, pad)
    put(g.out, "    },\n")
    put(g.out, pad)
    put(g.out, "    none => { if inbox.is_closed() { break } },\n")
    put(g.out, pad)
    put(g.out, "}\n")
    if service.idle_len > 0L { put(g.out, "        }\n") }
    if service.tick_ms > 0L {
        put(g.out, "        let after = config.env.now_ms()\n        if after >= next_tick {\n            let missed = (after - next_tick) / ")
        put_num(g.out, service.tick_ms)
        put(g.out, "L\n            ")
        put_name(g.out, name)
        put(g.out, "_on_tick(state, config, me, missed)\n            next_tick = next_tick + (missed + 1L) * ")
        put_num(g.out, service.tick_ms)
        put(g.out, "L\n        }\n")
    }
    put(g.out, "    }\n}\n")
    // start
    sep(g)
    put(g.out, "fn ")
    put_name(g.out, name)
    put(g.out, "_start(")
    var first_config = true
    for pair in service.config {
        if !first_config { put(g.out, ", ") }
        first_config = false
        put_name(g.out, pair.name)
        put(g.out, ": ")
        put_name(g.out, pair.text)
    }
    put(g.out, ") -> ")
    put_name(g.out, name)
    put(g.out, " {\n    var box: mailbox<")
    put_name(g.out, name)
    put(g.out, "Message, ")
    put_num(g.out, service.mailbox)
    put(g.out, "> = mailbox {}\n    spawn ")
    put_name(g.out, name)
    put(g.out, "_run(box.receiver(), box.sender()")
    for pair in service.config {
        put(g.out, ", ")
        put_name(g.out, pair.name)
    }
    put(g.out, ")\n    ")
    put_name(g.out, name)
    put(g.out, " { inbox: box.sender() }\n}\n")
    // the senders
    for handler in service.handlers {
        let has_fields = handler.params.count() > 0L || handler.reply.count() > 0L
        sep(g)
        if handler.reply.count() > 0L {
            put(g.out, "// sends ")
            put_name(g.out, handler.name)
            put(g.out, " and waits for the reply (none when the mailbox is full)\nfn ")
        } else {
            put(g.out, "// sends ")
            put_name(g.out, handler.name)
            put(g.out, "; false when the service's mailbox is full\nfn ")
        }
        put_name(g.out, name)
        put(g.out, "_")
        put_name(g.out, snake(handler.name))
        put(g.out, "(service: ")
        put_name(g.out, name)
        if handler.params.count() > 0L {
            put(g.out, ", ")
            put_pairs(g.out, handler.params, false)
        }
        if handler.reply.count() > 0L {
            put(g.out, ") -> Option<")
            put_name(g.out, handler.reply)
            put(g.out, "> {\n    var replies_box: mailbox<")
            put_name(g.out, handler.reply)
            put(g.out, ", 1> = mailbox {}\n    let replies = replies_box.receiver()\n    let message = ")
            put_name(g.out, name)
            put(g.out, "Message.")
            put_name(g.out, handler.name)
            put(g.out, "(")
            put_name(g.out, name)
            put_name(g.out, handler.name)
            put(g.out, "Args { ")
            for pair in handler.params {
                put_name(g.out, pair.name)
                put(g.out, ": ")
                put_name(g.out, pair.name)
                put(g.out, ", ")
            }
            put(g.out, "reply: replies_box.sender() })\n    match service.inbox.send(message) {\n")
            put(g.out, "        ok(_) => {\n            let answer = replies.recv_wait()\n            replies_box.release()\n            answer\n        },\n")
            put(g.out, "        err(_) => {\n            replies_box.release()\n            none\n        },\n    }\n}\n")
        } else {
            put(g.out, ") -> bool {\n    let message = ")
            put_name(g.out, name)
            put(g.out, "Message.")
            put_name(g.out, handler.name)
            if has_fields {
                put(g.out, "(")
                put_name(g.out, name)
                put_name(g.out, handler.name)
                put(g.out, "Args { ")
                var first_arg = true
                for pair in handler.params {
                    if !first_arg { put(g.out, ", ") }
                    first_arg = false
                    put_name(g.out, pair.name)
                    put(g.out, ": ")
                    put_name(g.out, pair.name)
                }
                put(g.out, " })")
            }
            put(g.out, "\n    match service.inbox.send(message) {\n        ok(_) => { true },\n        err(_) => { false },\n    }\n}\n")
        }
    }
    sep(g)
    put(g.out, "// asks the service to finish after the messages already queued\nfn ")
    put_name(g.out, name)
    put(g.out, "_stop(service: ")
    put_name(g.out, name)
    put(g.out, ") -> bool {\n    let message = ")
    put_name(g.out, name)
    put(g.out, "Message.Stop\n    match service.inbox.send(message) {\n        ok(_) => { true },\n        err(_) => { false },\n    }\n}\n")
}

fn less(a: Name, b: Name) -> bool {
    let n = if a.count() < b.count() { a.count() } else { b.count() }
    for index in 0L..n {
        if a[index] != b[index] { return a[index] < b[index] }
    }
    a.count() < b.count()
}

fn main(env: Env) {
    let arguments = env.args()
    if arguments.count() != 1L {
        ew(env, "usage: svc <package-dir>\n")
        env.exit(2)
    }
    let package = match arguments.get(0L) {
        some(value) => value,
        none => env.exit(2),
    }
    var package_text: Name = Bytes.empty()
    for index in 0L..package.count() {
        match package.get(index) {
            some(value) => { discard package_text.push(value) },
            none => (),
        }
    }
    var g = Gen {}
    var files: list<DirEntry, 256> = list {}
    match env.fs.list_with_extension(package, "svc", files) {
        ok(_) => (),
        err(_) => limit_error(env, "service files"),
    }
    var any = false
    for file_index in 0L..files.count() {
        let entry = files[file_index]
        if entry.kind == FileKind.File {
            any = true
            var path: Name = Bytes.empty()
            discard path.try_append(package_text)
            if path.count() == 0L || path[path.count() - 1L] != 47 { discard path.push((byte)47) }
            for index in 0L..entry.name.count() { discard path.push(entry.name[index]) }
            let file_path = match env.fs.join(package, entry.name) {
                ok(value) => value,
                err(_) => limit_error(env, "service path"),
            }
            var raw: Bytes max 524288 = Bytes.empty()
            match env.fs.read(file_path, raw) {
                ok(_) => (),
                err(_) => limit_error(env, "service file size"),
            }
            let base = g.all.count()
            for index in 0L..raw.count() { discard g.all.push(raw[index]) }
            let total = g.all.count()
            read_services(env, g, path, base, total)
        }
    }
    if !any { return }
    check_services(env, g)
    put(g.out, "// Generated by tools/svc.py from the package's .svc files; do not edit.\n")
    for index in 0L..g.services.count() { generate(env, g, index) }
    if g.edges.count() > 0L {
        // the message graph, sorted, each line once
        var sorted: list<Entry, 256> = list {}
        for edge in g.edges {
            var present = false
            for known in sorted { if names_equal(known.name, edge.name) { present = true } }
            if !present { discard sorted.push(Entry { name: edge.name }) }
        }
        for i in 1L..sorted.count() {
            var j = i
            while j > 0L && less(sorted[j].name, sorted[j - 1L].name) {
                let swap = sorted[j]
                sorted[j] = sorted[j - 1L]
                sorted[j - 1L] = swap
                j -= 1L
            }
        }
        put(g.out, "\n// message graph (service.handler -> target service):\n")
        var first = true
        for edge in sorted {
            if !first { put(g.out, "\n") }
            first = false
            put(g.out, "// ")
            put_name(g.out, edge.name)
        }
        put(g.out, "\n")
    }
    let target = match env.fs.join(package, "services.gen.nl") {
        ok(value) => value,
        err(_) => limit_error(env, "output path"),
    }
    var same = false
    var previous: Bytes max 524288 = Bytes.empty()
    match env.fs.read(target, previous) {
        ok(_) => {
            if previous.count() == g.out.count() {
                same = true
                for index in 0L..g.out.count() {
                    if previous[index] != g.out[index] { same = false }
                }
            }
        },
        err(_) => (),
    }
    if !same {
        var written: Bytes max 524288 = Bytes.empty()
        for index in 0L..g.out.count() { discard written.push(g.out[index]) }
        match env.fs.write(target, written) {
            ok(_) => (),
            err(_) => limit_error(env, "writing the output"),
        }
    }
}
