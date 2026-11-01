// The template compiler: `tmpl <package-dir>` turns the package's *.tpl files into next-lang functions in templates.gen.nl.
// Same input and output as the Python prototype it replaces (tools/tmpl.py); the template language is described there.
// Everything has a fixed capacity, chosen below; a template that does not fit says so.

const K_LONG: long = 1L
const K_INT: long = 2L
const K_BOOL: long = 3L
const K_BYTES: long = 4L
const K_ASCII: long = 5L
const K_LIST: long = 6L
const K_STRUCT: long = 7L

// where a hole sits: how its text is escaped
const X_TEXT: long = 1L
const X_ATTR: long = 2L
const X_URL: long = 3L
const X_JSON_STRING: long = 4L
const X_JSON_VALUE: long = 5L

// how the HTML scanner is placed
const M_TEXT: long = 1L
const M_TAG: long = 2L
const M_DQ: long = 3L
const M_SQ: long = 4L
const M_UNQ: long = 5L
const M_COMMENT: long = 6L
const M_RAW: long = 7L

const ASCII_LIMIT: long = 128L

type Name = Bytes max 256
type Line = Bytes max 256
type Buf = list<byte, 524288>

struct Ty {
    kind: long = 0L
    limit: long = 0L
    name: Name = Bytes.empty()
}

struct Field {
    owner: Name = Bytes.empty()
    name: Name = Bytes.empty()
    ty: Ty = Ty {}
}

struct Entry {
    name: Name = Bytes.empty()
}

struct Param {
    name: Name = Bytes.empty()
    text: Name = Bytes.empty()
    ty: Ty = Ty {}
}

// the scanner's place in the HTML (or JSON) written so far
struct Ctx {
    mode: long = 1L
    tag: Name = Bytes.empty()
    attr: Name = Bytes.empty()
    value: Name = Bytes.empty()
    raw_until: Name = Bytes.empty()
    closing: bool = false
    in_string: bool = false
    escaped: bool = false
}

struct HeaderPos {
    start: long = 0L
    end: long = 0L
    number: long = 0L
}

struct Hdr {
    found: bool = false
    html: bool = true
    name: Name = Bytes.empty()
    params_from: long = 0L
    params_to: long = 0L
    size: long = 0L
}

struct Gen {
    fields: list<Field, 1024> = list {}
    structs: list<Entry, 128> = list {}
    params: list<Param, 16> = list {}
    scopes: list<Param, 16> = list {}
    helper_names: list<Entry, 512> = list {}
    seen: list<Entry, 256> = list {}
    headers: list<HeaderPos, 128> = list {}
    helpers: Buf = list {}
    body: Buf = list {}
    functions: Buf = list {}
    output: Buf = list {}
    file: Buf = list {}
    previous: Buf = list {}
    lit: Buf = list {}
    path: Line = Bytes.empty()
    package_text: Line = Bytes.empty()
    ctx: Ctx = Ctx {}
    html: bool = true
    tname: Name = Bytes.empty()
    tline: long = 0L
    tstart: long = 0L
    tlen: long = 0L
    pos: long = 0L
    else_pending: bool = false
    else_indent: long = 0L
}

struct Parsed {
    size: long = 0L
    nodes: long = 0L
    stop: long = 0L
}

// ---------------------------------------------------------------- small helpers

fn ew(env: Env, text: Ascii max 1024) {
    match env.err.write(text.bytes()) { ok(_) => (), err(_) => env.exit(3) }
}

fn ew_name(env: Env, text: Line) {
    match env.err.write(text) { ok(_) => (), err(_) => env.exit(3) }
}

fn ew_small(env: Env, text: Name) {
    match env.err.write(text) { ok(_) => (), err(_) => env.exit(3) }
}

fn ew_num(env: Env, value: long) {
    match env.err.write(str(value).bytes()) { ok(_) => (), err(_) => env.exit(3) }
}

fn start_error(env: Env, g: Gen, line: long) {
    ew(env, "nlc: template error: ")
    ew_name(env, g.path)
    ew(env, ":")
    ew_num(env, line)
    ew(env, ": ")
}

fn end_error(env: Env) -> never {
    ew(env, "\n")
    env.exit(1)
}

fn limit_error(env: Env, what: Ascii max 128) -> never {
    ew(env, "nlc: template error: the generator's capacity for ")
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

fn put_line(out: write Buf, text: Line) {
    for index in 0L..text.count() { discard out.push(text[index]) }
}

fn put_buf(out: write Buf, text: Buf) {
    for index in 0L..text.count() { discard out.push(text[index]) }
}

fn put_num(out: write Buf, value: long) {
    let digits = str(value)
    for index in 0L..digits.len() { discard out.push(digits[index]) }
}

// The file at `path` into g.file.
fn load(env: Env, g: write Gen, path: Path) {
    var raw: Bytes max 524288 = Bytes.empty()
    match env.fs.read(path, raw) {
        ok(_) => (),
        err(_) => limit_error(env, "file size"),
    }
    g.file = list {}
    for index in 0L..raw.count() { discard g.file.push(raw[index]) }
}

fn nput(out: grow Name, text: Ascii max 64) {
    discard out.try_append(text.bytes())
}

fn nnum(out: grow Name, value: long) {
    discard out.try_append(str(value).bytes())
}

fn is_space(c: long) -> bool { c == 32L || (c >= 9L && c <= 13L) }
fn is_digit(c: long) -> bool { c >= 48L && c <= 57L }
fn is_alpha(c: long) -> bool { (c >= 65L && c <= 90L) || (c >= 97L && c <= 122L) }
fn is_word(c: long) -> bool { is_alpha(c) || is_digit(c) || c == 95L }
fn lower(c: long) -> long { if c >= 65L && c <= 90L { c + 32L } else { c } }

fn name_is(name: Name, text: Ascii max 64) -> bool {
    if name.count() != text.len() { return false }
    for index in 0L..text.len() {
        if name[index] != text[index] { return false }
    }
    true
}

fn names_equal(a: Name, b: Name) -> bool {
    if a.count() != b.count() { return false }
    for index in 0L..a.count() {
        if a[index] != b[index] { return false }
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

fn name_starts_with(name: Name, text: Ascii max 16) -> bool {
    if name.count() < text.len() { return false }
    for index in 0L..text.len() {
        if name[index] != text[index] { return false }
    }
    true
}

fn skip_spaces(text: Name, at: long) -> long {
    var index = at
    while index < text.count() && is_space(text[index].to_long()) { index += 1L }
    index
}

// ---------------------------------------------------------------- types and structs

// The Ty a type written in a struct or a parameter list means; anything else is a struct name.
fn parse_type(raw: Name) -> Ty {
    var start = 0L
    var end = raw.count()
    while start < end && is_space(raw[start].to_long()) { start += 1L }
    while end > start && is_space(raw[end - 1L].to_long()) { end -= 1L }
    var text: Name = Bytes.empty()
    for index in start..end { discard text.push(raw[index]) }
    if name_is(text, "long") { return Ty { kind: K_LONG } }
    if name_is(text, "int") { return Ty { kind: K_INT } }
    if name_is(text, "bool") { return Ty { kind: K_BOOL } }
    // (Bytes|Ascii)\s+max\s+(\d+)
    var word = 0L
    if name_starts_with(text, "Bytes") { word = K_BYTES } else if name_starts_with(text, "Ascii") { word = K_ASCII }
    if word != 0L {
        var at = 5L
        let after_name = at
        at = skip_spaces(text, at)
        if at > after_name && at + 3L <= text.count() && text[at] == 109 && text[at + 1L] == 97 && text[at + 2L] == 120 {
            at += 3L
            let after_max = at
            at = skip_spaces(text, at)
            if at > after_max && at < text.count() {
                var number = 0L
                var digits = true
                for index in at..text.count() {
                    let c = text[index].to_long()
                    if !is_digit(c) { digits = false } else { number = number * 10L + (c - 48L) }
                }
                if digits { return Ty { kind: word, limit: number } }
            }
        }
    }
    // list\s*<\s*(\w+)\s*,\s*(\d+)\s*>
    if name_starts_with(text, "list") {
        var at = skip_spaces(text, 4L)
        if at < text.count() && text[at] == 60 {
            at = skip_spaces(text, at + 1L)
            var element: Name = Bytes.empty()
            while at < text.count() && is_word(text[at].to_long()) {
                discard element.push(text[at])
                at += 1L
            }
            at = skip_spaces(text, at)
            if element.count() > 0L && at < text.count() && text[at] == 44 {
                at = skip_spaces(text, at + 1L)
                var number = 0L
                var count = 0L
                while at < text.count() && is_digit(text[at].to_long()) {
                    number = number * 10L + (text[at].to_long() - 48L)
                    count += 1L
                    at += 1L
                }
                at = skip_spaces(text, at)
                if count > 0L && at + 1L == text.count() && text[at] == 62 {
                    return Ty { kind: K_LIST, limit: number, name: element }
                }
            }
        }
    }
    Ty { kind: K_STRUCT, name: text }
}

fn find_struct(g: Gen, name: Name) -> bool {
    for entry in g.structs {
        if names_equal(entry.name, name) { return true }
    }
    false
}

// The field `field` of struct `owner`, or kind 0 when there is none (the last definition wins).
fn find_field(g: Gen, owner: Name, field: Name) -> Ty {
    var found = Ty {}
    for candidate in g.fields {
        if names_equal(candidate.owner, owner) && names_equal(candidate.name, field) { found = candidate.ty }
    }
    found
}

// One struct body: the lines `name: type` (a `= default` and a trailing comma are not part of the type).
fn read_struct_fields(env: Env, g: write Gen, owner: Name, from: long, to: long) {
    var line_start = from
    while line_start <= to {
        var line_end = line_start
        while line_end < to && g.file[line_end] != 10 { line_end += 1L }
        var start = line_start
        var end = line_end
        while start < end && is_space(g.file[start].to_long()) { start += 1L }
        while end > start && is_space(g.file[end - 1L].to_long()) { end -= 1L }
        if end > start {
            // cut at the first whitespace-equals-whitespace
            var cut = end
            for index in start..end {
                if cut == end && index > start && index + 1L < end && g.file[index] == 61 &&
                    is_space(g.file[index - 1L].to_long()) && is_space(g.file[index + 1L].to_long()) {
                    cut = index - 1L
                }
            }
            var name: Name = Bytes.empty()
            var at = start
            while at < cut && is_word(g.file[at].to_long()) {
                discard name.push(g.file[at])
                at += 1L
            }
            var probe = at
            while probe < cut && is_space(g.file[probe].to_long()) { probe += 1L }
            if name.count() > 0L && probe < cut && g.file[probe] == 58 {
                probe += 1L
                while probe < cut && is_space(g.file[probe].to_long()) { probe += 1L }
                var last = cut
                while last > probe && is_space(g.file[last - 1L].to_long()) { last -= 1L }
                if last > probe && g.file[last - 1L] == 44 { last -= 1L }
                while last > probe && is_space(g.file[last - 1L].to_long()) { last -= 1L }
                if last > probe {
                    var type_text: Name = Bytes.empty()
                    for index in probe..last { discard type_text.push(g.file[index]) }
                    let field = Field { owner, name, ty: parse_type(type_text) }
                    match g.fields.push(field) { ok(_) => (), err(_) => limit_error(env, "struct fields") }
                }
            }
        }
        line_start = line_end + 1L
    }
}

// Every `struct Name { ... }` in the package's .nl files (comments removed first).
fn read_structs(env: Env, g: write Gen, package: Arg, entries: write list<DirEntry, 256>) {
    match env.fs.list_with_extension(package, "nl", entries) {
        ok(_) => (),
        err(_) => limit_error(env, "source files"),
    }
    for entry_index in 0L..entries.count() {
        let entry = entries[entry_index]
        if entry.kind == FileKind.File {
            let path = match env.fs.join(package, entry.name) {
                ok(value) => value,
                err(_) => limit_error(env, "source path"),
            }
            load(env, g, path)
            // drop //-comments (to the end of the line), keeping the line breaks
            var in_comment = false
            g.lit = list {}
            for index in 0L..g.file.count() {
                let c = g.file[index]
                if in_comment {
                    if c == 10 {
                        in_comment = false
                        discard g.lit.push(c)
                    }
                } else if c == 47 && index + 1L < g.file.count() && g.file[index + 1L] == 47 {
                    in_comment = true
                } else {
                    discard g.lit.push(c)
                }
            }
            g.file = g.lit
            g.lit = list {}
            let length = g.file.count()
            var at = 0L
            while at < length {
                // \bstruct\s+(\w+)\s*\{([^}]*)\}
                let boundary = at == 0L || !is_word(g.file[at - 1L].to_long())
                if boundary && starts_with_at(g.file, at, length, "struct") {
                    var probe = at + 6L
                    let after_word = probe
                    while probe < length && is_space(g.file[probe].to_long()) { probe += 1L }
                    if probe > after_word {
                        var name: Name = Bytes.empty()
                        while probe < length && is_word(g.file[probe].to_long()) {
                            discard name.push(g.file[probe])
                            probe += 1L
                        }
                        while probe < length && is_space(g.file[probe].to_long()) { probe += 1L }
                        if name.count() > 0L && probe < length && g.file[probe] == 123 {
                            var close = probe + 1L
                            while close < length && g.file[close] != 125 { close += 1L }
                            if close < length {
                                match g.structs.push(Entry { name }) { ok(_) => (), err(_) => limit_error(env, "structs") }
                                read_struct_fields(env, g, name, probe + 1L, close)
                                at = close
                            }
                        }
                    }
                }
                at += 1L
            }
        }
    }
}

// ---------------------------------------------------------------- the scanner: where the text written so far has left the HTML or JSON

fn feed_html(start: Ctx, text: Buf) -> Ctx {
    var c = start
    let n = text.count()
    var index = 0L
    while index < n {
        let ch = text[index].to_long()
        var consumed = false
        if c.mode == M_TEXT {
            if ch == 60L && index + 3L < n && text[index + 1L] == 33 && text[index + 2L] == 45 && text[index + 3L] == 45 {
                c.mode = M_COMMENT
                index += 4L
                consumed = true
            } else if ch == 60L {
                var at = index + 1L
                var slash = false
                if at < n && text[at] == 47 {
                    slash = true
                    at += 1L
                }
                if at < n && is_alpha(text[at].to_long()) {
                    var name: Name = Bytes.empty()
                    while at < n && (is_alpha(text[at].to_long()) || is_digit(text[at].to_long()) || text[at] == 45) {
                        discard name.push((byte)lower(text[at].to_long()))
                        at += 1L
                    }
                    c.mode = M_TAG
                    c.tag = name
                    c.closing = slash
                    c.attr = Bytes.empty()
                    index = at
                    consumed = true
                }
            }
        } else if c.mode == M_COMMENT {
            if starts_with_at(text, index, n, "-->") {
                c.mode = M_TEXT
                index += 3L
                consumed = true
            }
        } else if c.mode == M_RAW {
            var matches = index + c.raw_until.count() <= n
            if matches {
                for k in 0L..c.raw_until.count() {
                    if lower(text[index + k].to_long()) != c.raw_until[k].to_long() { matches = false }
                }
            }
            if matches {
                var tag: Name = Bytes.empty()
                for k in 2L..c.raw_until.count() { discard tag.push(c.raw_until[k]) }
                c.mode = M_TAG
                c.tag = tag
                c.closing = true
                c.attr = Bytes.empty()
                index += c.raw_until.count()
                consumed = true
            }
        } else if c.mode == M_TAG {
            if ch == 62L {
                if (name_is(c.tag, "script") || name_is(c.tag, "style")) && !c.closing {
                    c.mode = M_RAW
                    var until: Name = Bytes.empty()
                    nput(until, "</")
                    discard until.try_append(c.tag)
                    c.raw_until = until
                } else {
                    c.mode = M_TEXT
                }
            } else if ch == 34L || ch == 39L {
                c.mode = if ch == 34L { M_DQ } else { M_SQ }
                c.value = Bytes.empty()
            } else if is_alpha(ch) {
                var attr: Name = Bytes.empty()
                var at = index
                while at < n && (is_word(text[at].to_long()) || text[at] == 58 || text[at] == 45) {
                    discard attr.push((byte)lower(text[at].to_long()))
                    at += 1L
                }
                c.attr = attr
                index = at
                if index < n && text[index] == 61 && index + 1L < n && text[index + 1L] != 34 && text[index + 1L] != 39 {
                    c.mode = M_UNQ
                }
                consumed = true
            }
        } else if c.mode == M_DQ || c.mode == M_SQ {
            if (c.mode == M_DQ && ch == 34L) || (c.mode == M_SQ && ch == 39L) {
                c.mode = M_TAG
            } else {
                discard c.value.push(text[index])
            }
        } else if c.mode == M_UNQ {
            if ch == 32L || ch == 9L || ch == 10L || ch == 62L {
                c.mode = if ch == 62L { M_TEXT } else { M_TAG }
            }
        }
        if !consumed { index += 1L }
    }
    c
}

fn feed_json(start: Ctx, text: Buf) -> Ctx {
    var c = start
    for index in 0L..text.count() {
        let ch = text[index].to_long()
        if c.in_string {
            if c.escaped {
                c.escaped = false
            } else if ch == 92L {
                c.escaped = true
            } else if ch == 34L {
                c.in_string = false
            }
        } else if ch == 34L {
            c.in_string = true
        }
    }
    c
}

fn ctx_same(a: Ctx, b: Ctx, html: bool) -> bool {
    if html {
        if a.mode != b.mode { return false }
        if a.mode == M_TEXT { return true }
        return names_equal(a.tag, b.tag) && names_equal(a.attr, b.attr) && names_equal(a.value, b.value) && names_equal(a.raw_until, b.raw_until)
    }
    a.in_string == b.in_string && a.escaped == b.escaped
}

fn is_url_attribute(attr: Name) -> bool {
    name_is(attr, "href") || name_is(attr, "src") || name_is(attr, "action") || name_is(attr, "formaction") ||
        name_is(attr, "poster") || name_is(attr, "cite") || name_is(attr, "data")
}

// How a hole at the scanner's present place is escaped; a place that cannot hold one is an error.
fn html_context(env: Env, g: Gen, line: long) -> long {
    let c = g.ctx
    if c.mode == M_TEXT { return X_TEXT }
    if c.mode == M_DQ || c.mode == M_SQ {
        if is_url_attribute(c.attr) {
            let v = c.value
            let ok_start = name_starts_with(v, "/") || name_starts_with(v, "http://") || name_starts_with(v, "https://") || name_starts_with(v, "#")
            if !ok_start {
                start_error(env, g, line)
                ew(env, "a hole may not start a `")
                ew_small(env, c.attr)
                ew(env, "` address (it could write `javascript:`); begin the address with `/` or `https://`")
                end_error(env)
            }
            return X_URL
        }
        if name_starts_with(c.attr, "on") || name_is(c.attr, "style") {
            start_error(env, g, line)
            ew(env, "a hole in `")
            ew_small(env, c.attr)
            ew(env, "` could run script; build it in the program instead")
            end_error(env)
        }
        return X_ATTR
    }
    start_error(env, g, line)
    if c.mode == M_RAW {
        ew(env, "a hole inside <")
        ew_small(env, c.tag)
        ew(env, "> could write script or style; not allowed")
    } else if c.mode == M_COMMENT {
        ew(env, "a hole inside an HTML comment")
    } else if c.mode == M_UNQ {
        ew(env, "put the attribute value in quotes before a hole")
    } else {
        ew(env, "a hole between a tag's attributes; put it inside a quoted value or in the text")
    }
    end_error(env)
}

// ---------------------------------------------------------------- the code written: helper functions, shared by all templates

// True when `name` is new (its source is to be written now).
fn register(env: Env, g: write Gen, name: Name) -> bool {
    for entry in g.helper_names {
        if names_equal(entry.name, name) { return false }
    }
    match g.helper_names.push(Entry { name }) { ok(_) => (), err(_) => limit_error(env, "helper functions") }
    if g.helpers.count() > 0L { put(g.helpers, "\n") }
    true
}

fn h_head(g: write Gen, name: Name, size: long) {
    put(g.helpers, "fn ")
    put_name(g.helpers, name)
    put(g.helpers, "(out: grow Bytes max ")
    put_num(g.helpers, size)
}

fn h_lit(env: Env, g: write Gen, size: long) -> Name {
    var name: Name = Bytes.empty()
    nput(name, "tpl_lit_")
    nnum(name, size)
    if register(env, g, name) {
        h_head(g, name, size)
        put(g.helpers, ", text: Ascii max 128) {\n    discard out.try_append(text.bytes())\n}\n")
    }
    name
}

fn h_num(env: Env, g: write Gen, size: long) -> Name {
    var name: Name = Bytes.empty()
    nput(name, "tpl_num_")
    nnum(name, size)
    if register(env, g, name) {
        h_head(g, name, size)
        put(g.helpers, """, value: long) {
    var rest = value
    if rest < 0L {
        discard out.push((byte)45)
        rest = 0L - rest
    }
    var digits: list<long, 20> = list {}
    for step in 0L..20L {
        discard digits.push(rest % 10L)
        rest = rest / 10L
        if rest == 0L { break }
    }
    var index = digits.count()
    for position in 0L..digits.count() {
        index -= 1L
        discard out.push((byte)(48L + digits[index]))
    }
}
""")
    }
    name
}

fn h_money(env: Env, g: write Gen, size: long) -> Name {
    let number = h_num(env, g, size)
    var name: Name = Bytes.empty()
    nput(name, "tpl_money_")
    nnum(name, size)
    if register(env, g, name) {
        h_head(g, name, size)
        put(g.helpers, ", cents: long) {\n    ")
        put_name(g.helpers, number)
        put(g.helpers, """(out, cents / 100L)
    discard out.push((byte)46)
    let rest = cents % 100L
    discard out.push((byte)(48L + rest / 10L))
    discard out.push((byte)(48L + rest % 10L))
}
""")
    }
    name
}

fn h_bool(env: Env, g: write Gen, size: long) -> Name {
    let lit = h_lit(env, g, size)
    var name: Name = Bytes.empty()
    nput(name, "tpl_bool_")
    nnum(name, size)
    if register(env, g, name) {
        h_head(g, name, size)
        put(g.helpers, ", value: bool) {\n    if value { ")
        put_name(g.helpers, lit)
        put(g.helpers, "(out, \"true\") } else { ")
        put_name(g.helpers, lit)
        put(g.helpers, "(out, \"false\") }\n}\n")
    }
    name
}

fn h_hex(env: Env, g: write Gen, size: long) -> Name {
    var name: Name = Bytes.empty()
    nput(name, "tpl_hex_")
    nnum(name, size)
    if register(env, g, name) {
        h_head(g, name, size)
        put(g.helpers, ", digit: long) {\n    if digit < 10L { discard out.push((byte)(48L + digit)) } else { discard out.push((byte)(55L + digit)) }\n}\n")
    }
    name
}

fn lit_case(g: write Gen, lead: Ascii max 64, lit: Name, tail: Ascii max 64) {
    put(g.helpers, lead)
    put_name(g.helpers, lit)
    put(g.helpers, tail)
}

fn h_escape(env: Env, g: write Gen, context: long, kind: long, limit: long, size: long) -> Name {
    let lit = h_lit(env, g, size)
    let hexd = h_hex(env, g, size)
    var name: Name = Bytes.empty()
    if context == X_JSON_VALUE {
        nput(name, "tpl_json_quoted_")
    } else if context == X_TEXT {
        nput(name, "tpl_html_text_")
    } else if context == X_ATTR {
        nput(name, "tpl_html_attr_")
    } else if context == X_URL {
        nput(name, "tpl_html_url_")
    } else {
        nput(name, "tpl_json_string_")
    }
    nput(name, if kind == K_BYTES { "bytes_" } else { "ascii_" })
    nnum(name, limit)
    nput(name, "_")
    nnum(name, size)
    if register(env, g, name) {
        let get = if kind == K_BYTES { "value[index]" } else { "value.bytes()[index]" }
        h_head(g, name, size)
        put(g.helpers, ", value: ")
        put(g.helpers, if kind == K_BYTES { "Bytes" } else { "Ascii" })
        put(g.helpers, " max ")
        put_num(g.helpers, limit)
        put(g.helpers, ") {\n")
        if context == X_JSON_VALUE { put(g.helpers, "    discard out.push((byte)34)\n") }
        put(g.helpers, "    for index in 0L..")
        put(g.helpers, if kind == K_BYTES { "value.count()" } else { "value.len()" })
        put(g.helpers, " {\n        let c = ")
        put(g.helpers, get)
        put(g.helpers, ".to_long()\n")
        if context == X_TEXT || context == X_ATTR {
            lit_case(g, "        if c == 60L { ", lit, "(out, \"&lt;\") }\n")
            lit_case(g, "        else if c == 62L { ", lit, "(out, \"&gt;\") }\n")
            lit_case(g, "        else if c == 38L { ", lit, "(out, \"&amp;\") }\n")
            lit_case(g, "        else if c == 34L { ", lit, "(out, \"&quot;\") }\n")
            lit_case(g, "        else if c == 39L { ", lit, "(out, \"&#39;\") }\n")
            put(g.helpers, "        else { discard out.push(")
            put(g.helpers, get)
            put(g.helpers, ") }\n")
        } else if context == X_JSON_STRING || context == X_JSON_VALUE {
            lit_case(g, "        if c == 34L { ", lit, "(out, \"\x5c\x5c\x5c\"\") }\n")
            lit_case(g, "        else if c == 92L { ", lit, "(out, \"\x5c\x5c\x5c\x5c\") }\n")
            lit_case(g, "        else if c == 10L { ", lit, "(out, \"\x5c\x5cn\") }\n")
            put(g.helpers, "        else if c < 32L {\n")
            lit_case(g, "            ", lit, "(out, \"\x5c\x5cu00\")\n")
            lit_case(g, "            ", hexd, "(out, c / 16L)\n")
            lit_case(g, "            ", hexd, "(out, c % 16L)\n")
            put(g.helpers, "        }\n        else { discard out.push(")
            put(g.helpers, get)
            put(g.helpers, ") }\n")
        } else {
            put(g.helpers, "        let unreserved = (c >= 48L && c <= 57L) || (c >= 65L && c <= 90L) || (c >= 97L && c <= 122L) || c == 45L || c == 46L || c == 95L || c == 126L\n")
            put(g.helpers, "        if unreserved { discard out.push(")
            put(g.helpers, get)
            put(g.helpers, ") }\n        else {\n            discard out.push((byte)37)\n")
            lit_case(g, "            ", hexd, "(out, c / 16L)\n")
            lit_case(g, "            ", hexd, "(out, c % 16L)\n")
            put(g.helpers, "        }\n")
        }
        put(g.helpers, "    }\n")
        if context == X_JSON_VALUE { put(g.helpers, "    discard out.push((byte)34)\n") }
        put(g.helpers, "}\n")
    }
    name
}

// ---------------------------------------------------------------- the body of one function

// A new line of the function's body at `indent`; a pending `} else {` goes first.
fn begin_line(g: write Gen, indent: long) {
    if g.else_pending {
        g.else_pending = false
        for step in 0L..g.else_indent { put(g.body, "    ") }
        put(g.body, "} else {\n")
    }
    for step in 0L..indent { put(g.body, "    ") }
}

fn end_line(g: write Gen) {
    put(g.body, "\n")
}

fn tb(g: Gen, offset: long) -> long {
    g.file[g.tstart + offset].to_long()
}

fn line_at(g: Gen, offset: long) -> long {
    var line = g.tline + 1L
    for index in 0L..offset {
        if tb(g, index) == 10L { line += 1L }
    }
    line
}

fn hole_size(hole: Ty, filter: long, context: long) -> long {
    if filter == 1L { return 22L }
    if filter == 2L { return hole.limit }
    if hole.kind == K_LONG { return 20L }
    if hole.kind == K_INT { return 11L }
    if hole.kind == K_BOOL { return 5L }
    if context == X_TEXT || context == X_ATTR { return hole.limit * 6L }
    if context == X_URL { return hole.limit * 3L }
    if context == X_JSON_STRING { return hole.limit * 6L }
    hole.limit * 6L + 2L
}

// Writes the literal text gathered so far as calls of the literal helper, in chunks the helper takes.
fn flush(env: Env, g: write Gen, indent: long, bsize: long, result: write Parsed) {
    if g.lit.count() == 0L { return }
    result.nodes += 1L
    result.size += g.lit.count()
    var scanner = g.ctx
    scanner = if g.html { feed_html(scanner, g.lit) } else { feed_json(scanner, g.lit) }
    g.ctx = scanner
    let helper = h_lit(env, g, bsize)
    var start = 0L
    while start < g.lit.count() {
        var end = start + ASCII_LIMIT
        if end > g.lit.count() { end = g.lit.count() }
        begin_line(g, indent)
        put_name(g.body, helper)
        put(g.body, "(out, \"")
        for index in start..end {
            let c = g.lit[index]
            if c == 92 {
                put(g.body, "\x5c\x5c")
            } else if c == 34 {
                put(g.body, "\x5c\"")
            } else if c == 10 {
                put(g.body, "\x5cn")
            } else if c == 9 {
                put(g.body, "\x5ct")
            } else {
                discard g.body.push(c)
            }
        }
        put(g.body, "\")")
        end_line(g)
        start = end
    }
    g.lit = list {}
}

// ---------------------------------------------------------------- names in holes, loops and conditions

fn error_resolve(env: Env, g: Gen, line: long) {
    start_error(env, g, line)
}

// The next dotted segment of `expression` starting at `from`; sets `next` to where the one after starts (or -1).
fn segment(expression: Line, from: long, out: grow Name) -> long {
    var at = from
    while at < expression.count() && expression[at] != 46 {
        discard out.push(expression[at])
        at += 1L
    }
    if at < expression.count() { at + 1L } else { -1L }
}

fn unknown_field(env: Env, g: Gen, line: long, expression: Line, field: Name) -> never {
    start_error(env, g, line)
    ew(env, "`")
    ew_name(env, expression)
    ew(env, "` names no field `")
    ew_small(env, field)
    ew(env, "`")
    end_error(env)
}

// What a dotted name in a hole or a condition is: a loop variable or a parameter, then fields.
fn resolve(env: Env, g: Gen, expression: Line, line: long) -> Ty {
    var first: Name = Bytes.empty()
    var next = segment(expression, 0L, first)
    var ty = Ty {}
    var found = false
    var index = g.scopes.count()
    while index > 0L && !found {
        index -= 1L
        if names_equal(g.scopes[index].name, first) {
            ty = Ty { kind: K_STRUCT, name: g.scopes[index].ty.name }
            found = true
        }
    }
    if !found {
        for candidate in g.params {
            if names_equal(candidate.name, first) {
                ty = candidate.ty
                found = true
            }
        }
    }
    if !found {
        start_error(env, g, line)
        ew(env, "`")
        ew_small(env, first)
        ew(env, "` is not a parameter of template ")
        ew_small(env, g.tname)
        end_error(env)
    }
    while next >= 0L {
        var field: Name = Bytes.empty()
        next = segment(expression, next, field)
        if ty.kind != K_STRUCT || !find_struct(g, ty.name) { unknown_field(env, g, line, expression, field) }
        let looked = find_field(g, ty.name, field)
        if looked.kind == 0L { unknown_field(env, g, line, expression, field) }
        ty = looked
    }
    if ty.kind == K_STRUCT {
        start_error(env, g, line)
        ew(env, "`")
        ew_name(env, expression)
        ew(env, "` is a struct; name one of its fields")
        end_error(env)
    }
    if ty.kind == K_LIST {
        start_error(env, g, line)
        ew(env, "`")
        ew_name(env, expression)
        ew(env, "` is a list; loop over it with {#for item in ")
        ew_name(env, expression)
        ew(env, "}")
        end_error(env)
    }
    ty
}

fn resolve_list(env: Env, g: Gen, expression: Line, line: long) -> Ty {
    var first: Name = Bytes.empty()
    var next = segment(expression, 0L, first)
    var ty = Ty {}
    for candidate in g.params {
        if names_equal(candidate.name, first) { ty = candidate.ty }
    }
    while next >= 0L {
        var field: Name = Bytes.empty()
        next = segment(expression, next, field)
        if ty.kind != K_STRUCT || !find_struct(g, ty.name) { unknown_field(env, g, line, expression, field) }
        let looked = find_field(g, ty.name, field)
        if looked.kind == 0L { unknown_field(env, g, line, expression, field) }
        ty = looked
    }
    if ty.kind != K_LIST {
        start_error(env, g, line)
        ew(env, "`{#for}` needs a list<Row, N>, and `")
        ew_name(env, expression)
        ew(env, "` is not one")
        end_error(env)
    }
    if !find_struct(g, ty.name) {
        start_error(env, g, line)
        ew(env, "the list's element type `")
        ew_small(env, ty.name)
        ew(env, "` is not a struct of the package")
        end_error(env)
    }
    ty
}

// ---------------------------------------------------------------- parsing a template body, writing its code as it goes

fn copy_range(g: Gen, from: long, to: long) -> Line {
    var out: Line = Bytes.empty()
    for index in from..to { discard out.push(g.file[g.tstart + index]) }
    out
}

// Parses up to the end of the body or a {#else} / {#end} this level may stop at (stop = 1 or 2), writing the code at `indent`.
recursive fn parse_nodes(env: Env, g: write Gen, allow_else: bool, allow_end: bool, indent: long, bsize: long) -> Parsed {
    var result = Parsed {}
    while g.pos < g.tlen {
        let c = tb(g, g.pos)
        let next = if g.pos + 1L < g.tlen { tb(g, g.pos + 1L) } else { 0L }
        if c == 123L && next == 123L {
            discard g.lit.push((byte)123)
            g.pos += 2L
        } else if c == 125L && next == 125L {
            discard g.lit.push((byte)125)
            g.pos += 2L
        } else if c == 123L {
            var close = g.pos
            while close < g.tlen && tb(g, close) != 125L { close += 1L }
            let line = line_at(g, g.pos)
            if close >= g.tlen {
                start_error(env, g, line)
                ew(env, "a `{` with no closing `}`; write `{{` for a brace")
                end_error(env)
            }
            // the text between the braces, with spaces trimmed
            var from = g.pos + 1L
            var to = close
            while from < to && is_space(tb(g, from)) { from += 1L }
            while to > from && is_space(tb(g, to - 1L)) { to -= 1L }
            if to - from > 250L { limit_error(env, "a name inside braces") }
            let inside = copy_range(g, from, to)
            if inside.count() > 0L && inside[0] == 35 {
                // words
                var w0: Name = Bytes.empty()
                var w1: Name = Bytes.empty()
                var w2: Name = Bytes.empty()
                var w3: Line = Bytes.empty()
                var words = 0L
                var at = 0L
                while at < inside.count() {
                    while at < inside.count() && is_space(inside[at].to_long()) { at += 1L }
                    if at < inside.count() {
                        var word: Line = Bytes.empty()
                        while at < inside.count() && !is_space(inside[at].to_long()) {
                            discard word.push(inside[at])
                            at += 1L
                        }
                        if words == 0L { w0 = word } else if words == 1L { w1 = word } else if words == 2L { w2 = word } else if words == 3L { w3 = word }
                        words += 1L
                    }
                }
                if allow_else && name_is(w0, "#else") {
                    flush(env, g, indent, bsize, result)
                    g.pos = close + 1L
                    result.stop = 1L
                    return result
                }
                if allow_end && name_is(w0, "#end") {
                    flush(env, g, indent, bsize, result)
                    g.pos = close + 1L
                    result.stop = 2L
                    return result
                }
                if name_is(w0, "#for") && words == 4L && name_is(w2, "in") {
                    flush(env, g, indent, bsize, result)
                    g.pos = close + 1L
                    let list_type = resolve_list(env, g, w3, line)
                    let before = g.ctx
                    begin_line(g, indent)
                    put(g.body, "for ")
                    put_name(g.body, w1)
                    put(g.body, " in ")
                    put_line(g.body, w3)
                    put(g.body, " {")
                    end_line(g)
                    match g.scopes.push(Param { name: w1, ty: Ty { kind: K_STRUCT, name: list_type.name } }) {
                        ok(_) => (),
                        err(_) => limit_error(env, "nested loops"),
                    }
                    let inner = parse_nodes(env, g, false, true, indent + 1L, bsize)
                    match g.scopes.pop() { some(_) => (), none => () }
                    if inner.stop != 2L {
                        start_error(env, g, line)
                        ew(env, "`{#for}` has no `{#end}`")
                        end_error(env)
                    }
                    if !ctx_same(g.ctx, before, g.html) {
                        start_error(env, g, line)
                        ew(env, "the body of this `{#for}` leaves the ")
                        ew(env, if g.html { "html" } else { "json" })
                        ew(env, " in a different place than it found it (an open tag or string); close it in every round")
                        end_error(env)
                    }
                    begin_line(g, indent)
                    put(g.body, "}")
                    end_line(g)
                    result.nodes += 1L
                    result.size += list_type.limit * inner.size
                } else if name_is(w0, "#if") && words == 2L {
                    flush(env, g, indent, bsize, result)
                    g.pos = close + 1L
                    let condition = resolve(env, g, w1, line)
                    if condition.kind != K_BOOL {
                        start_error(env, g, line)
                        ew(env, "`{#if ")
                        ew_small(env, w1)
                        ew(env, "}` needs a bool")
                        end_error(env)
                    }
                    let before = g.ctx
                    begin_line(g, indent)
                    put(g.body, "if ")
                    put_name(g.body, w1)
                    put(g.body, " {")
                    end_line(g)
                    let then_part = parse_nodes(env, g, true, true, indent + 1L, bsize)
                    let after_then = g.ctx
                    var other = Parsed {}
                    var stop = then_part.stop
                    g.ctx = before
                    if stop == 1L {
                        g.else_pending = true
                        g.else_indent = indent
                        other = parse_nodes(env, g, false, true, indent + 1L, bsize)
                        stop = other.stop
                        g.else_pending = false
                    }
                    if stop != 2L {
                        start_error(env, g, line)
                        ew(env, "`{#if}` has no `{#end}`")
                        end_error(env)
                    }
                    if !ctx_same(g.ctx, after_then, g.html) {
                        start_error(env, g, line)
                        ew(env, "the two sides of this `{#if}` leave the ")
                        ew(env, if g.html { "html" } else { "json" })
                        ew(env, " in different places (an open tag or string); close it in both")
                        end_error(env)
                    }
                    begin_line(g, indent)
                    put(g.body, "}")
                    end_line(g)
                    result.nodes += 1L
                    result.size += if then_part.size > other.size { then_part.size } else { other.size }
                } else {
                    start_error(env, g, line)
                    ew(env, "unknown `{")
                    ew_name(env, inside)
                    ew(env, "}`")
                    end_error(env)
                }
            } else {
                flush(env, g, indent, bsize, result)
                g.pos = close + 1L
                // {expression|filter}
                var bar = inside.count()
                for index in 0L..inside.count() {
                    if bar == inside.count() && inside[index] == 124 { bar = index }
                }
                var expression: Line = Bytes.empty()
                var filter: Line = Bytes.empty()
                var e_from = 0L
                var e_to = bar
                while e_from < e_to && is_space(inside[e_from].to_long()) { e_from += 1L }
                while e_to > e_from && is_space(inside[e_to - 1L].to_long()) { e_to -= 1L }
                for index in e_from..e_to { discard expression.push(inside[index]) }
                if bar < inside.count() {
                    var f_from = bar + 1L
                    var f_to = inside.count()
                    while f_from < f_to && is_space(inside[f_from].to_long()) { f_from += 1L }
                    while f_to > f_from && is_space(inside[f_to - 1L].to_long()) { f_to -= 1L }
                    for index in f_from..f_to { discard filter.push(inside[index]) }
                }
                let hole = resolve(env, g, expression, line)
                var filter_kind = 0L
                if filter.count() > 0L {
                    if name_is(filter, "money") { filter_kind = 1L } else if name_is(filter, "raw") { filter_kind = 2L } else {
                        start_error(env, g, line)
                        ew(env, "unknown filter `")
                        ew_name(env, filter)
                        ew(env, "` (the filters are `money` and `raw`)")
                        end_error(env)
                    }
                }
                if filter_kind == 2L && hole.kind != K_BYTES && hole.kind != K_ASCII {
                    start_error(env, g, line)
                    ew(env, "`raw` writes text as it is, and `")
                    ew_name(env, expression)
                    ew(env, "` is not text")
                    end_error(env)
                }
                if filter_kind == 1L && hole.kind != K_LONG {
                    start_error(env, g, line)
                    ew(env, "`money` writes a long number of cents")
                    end_error(env)
                }
                var context = X_JSON_VALUE
                if g.html {
                    context = html_context(env, g, line)
                    if filter_kind == 2L && context != X_TEXT {
                        start_error(env, g, line)
                        ew(env, "`raw` is only allowed in HTML text, not inside a tag or attribute")
                        end_error(env)
                    }
                } else if g.ctx.in_string {
                    context = X_JSON_STRING
                }
                begin_line(g, indent)
                if filter_kind == 1L {
                    put_name(g.body, h_money(env, g, bsize))
                    put(g.body, "(out, ")
                    put_line(g.body, expression)
                    put(g.body, ")")
                } else if filter_kind == 2L {
                    put(g.body, "discard out.try_append(")
                    put_line(g.body, expression)
                    if hole.kind == K_ASCII { put(g.body, ".bytes()") }
                    put(g.body, ")")
                } else if hole.kind == K_LONG {
                    put_name(g.body, h_num(env, g, bsize))
                    put(g.body, "(out, ")
                    put_line(g.body, expression)
                    put(g.body, ")")
                } else if hole.kind == K_INT {
                    put_name(g.body, h_num(env, g, bsize))
                    put(g.body, "(out, ")
                    put_line(g.body, expression)
                    put(g.body, ".to_long())")
                } else if hole.kind == K_BOOL {
                    put_name(g.body, h_bool(env, g, bsize))
                    put(g.body, "(out, ")
                    put_line(g.body, expression)
                    put(g.body, ")")
                } else {
                    put_name(g.body, h_escape(env, g, context, hole.kind, hole.limit, bsize))
                    put(g.body, "(out, ")
                    put_line(g.body, expression)
                    put(g.body, ")")
                }
                end_line(g)
                result.nodes += 1L
                result.size += hole_size(hole, filter_kind, context)
            }
        } else {
            if c > 126L || (c < 32L && c != 10L && c != 9L) {
                start_error(env, g, line_at(g, g.pos))
                ew(env, "template text must be ASCII (write non-ASCII characters as entities or \x5cu escapes)")
                end_error(env)
            }
            discard g.lit.push((byte)c)
            g.pos += 1L
        }
    }
    flush(env, g, indent, bsize, result)
    result
}

// ---------------------------------------------------------------- reading a template file

// Whether the line [start, end) of the file is `html|json template name(params) max N`.
fn match_header(g: Gen, start: long, end: long) -> Hdr {
    var h = Hdr {}
    var at = start
    if starts_with_at(g.file, at, end, "html") {
        h.html = true
    } else if starts_with_at(g.file, at, end, "json") {
        h.html = false
    } else {
        return h
    }
    at += 4L
    var probe = at
    while probe < end && is_space(g.file[probe].to_long()) { probe += 1L }
    if probe == at { return h }
    if !starts_with_at(g.file, probe, end, "template") { return h }
    at = probe + 8L
    probe = at
    while probe < end && is_space(g.file[probe].to_long()) { probe += 1L }
    if probe == at { return h }
    var name: Name = Bytes.empty()
    while probe < end && is_word(g.file[probe].to_long()) {
        discard name.push(g.file[probe])
        probe += 1L
    }
    if name.count() == 0L { return h }
    while probe < end && is_space(g.file[probe].to_long()) { probe += 1L }
    if probe >= end || g.file[probe] != 40 { return h }
    let paren = probe
    // the end of the line: \)\s+max\s+(\d+)\s*$
    var e = end
    while e > start && is_space(g.file[e - 1L].to_long()) { e -= 1L }
    var d = e
    var size = 0L
    var scale = 1L
    while d > start && is_digit(g.file[d - 1L].to_long()) {
        size += (g.file[d - 1L].to_long() - 48L) * scale
        scale *= 10L
        d -= 1L
    }
    if d == e { return h }
    var w = d
    while w > start && is_space(g.file[w - 1L].to_long()) { w -= 1L }
    if w == d || w < start + 3L { return h }
    if g.file[w - 3L] != 109 || g.file[w - 2L] != 97 || g.file[w - 1L] != 120 { return h }
    var q = w - 3L
    let max_start = q
    while q > start && is_space(g.file[q - 1L].to_long()) { q -= 1L }
    if q == max_start || q - 1L <= paren || g.file[q - 1L] != 41 { return h }
    h.found = true
    h.name = name
    h.params_from = paren + 1L
    h.params_to = q - 1L
    h.size = size
    h
}

fn strip_name(g: Gen, from: long, to: long) -> Name {
    var a = from
    var b = to
    while a < b && is_space(g.file[a].to_long()) { a += 1L }
    while b > a && is_space(g.file[b - 1L].to_long()) { b -= 1L }
    var out: Name = Bytes.empty()
    for index in a..b { discard out.push(g.file[index]) }
    out
}

// The parameter list, split at commas outside <>, each as name: type.
fn read_params(env: Env, g: write Gen, from: long, to: long) {
    g.params = list {}
    var depth = 0L
    var item_start = from
    var any_text = false
    for index in from..to + 1L {
        let at_end = index == to
        let c = if at_end { 0L } else { g.file[index].to_long() }
        if c == 60L { depth += 1L } else if c == 62L { depth -= 1L }
        if at_end || (c == 44L && depth == 0L) {
            // an item between commas; the last one only counts when it holds more than spaces
            var blank = true
            for k in item_start..index { if !is_space(g.file[k].to_long()) { blank = false } }
            if !(at_end && blank) {
                var colon = index
                for k in item_start..index { if colon == index && g.file[k] == 58 { colon = k } }
                let name = strip_name(g, item_start, colon)
                var type_text: Name = Bytes.empty()
                if colon < index { type_text = strip_name(g, colon + 1L, index) }
                match g.params.push(Param { name, text: type_text, ty: parse_type(type_text) }) {
                    ok(_) => (),
                    err(_) => limit_error(env, "template parameters"),
                }
            }
            item_start = index + 1L
        }
    }
}

fn contains_name(entries: list<Entry, 256>, name: Name) -> bool {
    for entry in entries {
        if names_equal(entry.name, name) { return true }
    }
    false
}

fn compile_template(env: Env, g: write Gen, hdr: Hdr, line_no: long, body_start: long, body_end: long) {
    g.tname = hdr.name
    g.tline = line_no
    g.html = hdr.html
    g.tstart = body_start
    g.tlen = body_end - body_start
    if g.tlen > 0L && g.file[body_end - 1L] == 10 { g.tlen -= 1L }
    if contains_name(g.seen, hdr.name) {
        start_error(env, g, line_no)
        ew(env, "template ")
        ew_small(env, hdr.name)
        ew(env, " is defined twice")
        end_error(env)
    }
    match g.seen.push(Entry { name: hdr.name }) { ok(_) => (), err(_) => limit_error(env, "templates") }
    read_params(env, g, hdr.params_from, hdr.params_to)
    g.scopes = list {}
    g.ctx = Ctx {}
    g.pos = 0L
    g.lit = list {}
    g.body = list {}
    g.else_pending = false
    let parsed = parse_nodes(env, g, false, false, 1L, hdr.size)
    if parsed.size > hdr.size {
        start_error(env, g, line_no)
        ew(env, "template ")
        ew_small(env, hdr.name)
        ew(env, " can write up to ")
        ew_num(env, parsed.size)
        ew(env, " bytes but its buffer holds ")
        ew_num(env, hdr.size)
        ew(env, "; make `max` at least ")
        ew_num(env, parsed.size)
        ew(env, " or shorten the template")
        end_error(env)
    }
    if g.functions.count() > 0L { put(g.functions, "\n") }
    put(g.functions, "// ")
    put(g.functions, if hdr.html { "html" } else { "json" })
    put(g.functions, " template ")
    put_name(g.functions, hdr.name)
    put(g.functions, ": writes at most ")
    put_num(g.functions, parsed.size)
    put(g.functions, " bytes\nfn render_")
    put_name(g.functions, hdr.name)
    put(g.functions, "(out: grow Bytes max ")
    put_num(g.functions, hdr.size)
    for param in g.params {
        put(g.functions, ", ")
        put_name(g.functions, param.name)
        put(g.functions, ": ")
        put_name(g.functions, param.text)
    }
    put(g.functions, ") {\n")
    if g.body.count() > 0L { put_buf(g.functions, g.body) } else { put(g.functions, "\n") }
    put(g.functions, "}\n")
}

fn read_templates(env: Env, g: write Gen) {
    let total = g.file.count()
    // the lines that are headers
    g.headers = list {}
    var line_start = 0L
    var number = 1L
    while line_start <= total {
        var line_end = line_start
        while line_end < total && g.file[line_end] != 10 { line_end += 1L }
        let header = match_header(g, line_start, line_end)
        if header.found {
            match g.headers.push(HeaderPos { start: line_start, end: line_end, number }) {
                ok(_) => (),
                err(_) => limit_error(env, "templates in a file"),
            }
        } else if g.headers.count() == 0L {
            var blank = true
            for k in line_start..line_end { if !is_space(g.file[k].to_long()) { blank = false } }
            let comment = line_end - line_start >= 2L && g.file[line_start] == 47 && g.file[line_start + 1L] == 47
            if !blank && !comment {
                start_error(env, g, number)
                ew(env, "expected a template header, e.g. `html template page(row: Row) max 512`")
                end_error(env)
            }
        }
        line_start = line_end + 1L
        number += 1L
    }
    for index in 0L..g.headers.count() {
        let position = g.headers[index]
        let header = match_header(g, position.start, position.end)
        var body_start = position.end + 1L
        if body_start > total { body_start = total }
        var body_end = total
        if index + 1L < g.headers.count() { body_end = g.headers[index + 1L].start - 1L }
        if body_end < body_start { body_end = body_start }
        compile_template(env, g, header, position.number, body_start, body_end)
    }
}

fn main(env: Env) {
    let arguments = env.args()
    if arguments.count() != 1L {
        ew(env, "usage: tmpl <package-dir>\n")
        env.exit(2)
    }
    let package = match arguments.get(0L) {
        some(value) => value,
        none => env.exit(2),
    }
    var g = Gen {}
    for index in 0L..package.count() {
        match package.get(index) {
            some(value) => { discard g.package_text.push(value) },
            none => (),
        }
    }
    var sources: list<DirEntry, 256> = list {}
    read_structs(env, g, package, sources)
    var templates: list<DirEntry, 256> = list {}
    match env.fs.list_with_extension(package, "tpl", templates) {
        ok(_) => (),
        err(_) => limit_error(env, "template files"),
    }
    var any = false
    for template_index in 0L..templates.count() {
        let entry = templates[template_index]
        if entry.kind == FileKind.File {
            any = true
            g.path = g.package_text
            if g.path.count() == 0L || g.path[g.path.count() - 1L] != 47 { discard g.path.push((byte)47) }
            for index in 0L..entry.name.count() { discard g.path.push(entry.name[index]) }
            let path = match env.fs.join(package, entry.name) {
                ok(value) => value,
                err(_) => limit_error(env, "template path"),
            }
            load(env, g, path)
            read_templates(env, g)
        }
    }
    if !any { return }
    put(g.output, "// Generated by tools/tmpl.py from the package's .tpl files; do not edit.\n\n")
    put_buf(g.output, g.helpers)
    put(g.output, "\n")
    put_buf(g.output, g.functions)
    let target = match env.fs.join(package, "templates.gen.nl") {
        ok(value) => value,
        err(_) => limit_error(env, "output path"),
    }
    var same = false
    var previous: Bytes max 524288 = Bytes.empty()
    match env.fs.read(target, previous) {
        ok(_) => {
            if previous.count() == g.output.count() {
                same = true
                for index in 0L..g.output.count() {
                    if previous[index] != g.output[index] { same = false }
                }
            }
        },
        err(_) => (),
    }
    if !same {
        var written: Bytes max 524288 = Bytes.empty()
        for index in 0L..g.output.count() { discard written.push(g.output[index]) }
        match env.fs.write(target, written) {
            ok(_) => (),
            err(_) => limit_error(env, "writing the output"),
        }
    }
}
