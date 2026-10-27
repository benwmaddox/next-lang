// Template::Parse: render an HTML template by scanning for {{ key }} and looking keys up in a map.
const TEST_COUNT: long = 10L
const TEST_ITERATIONS: long = 2L
const RUN_COUNT: long = 50000L
const RUN_ITERATIONS: long = 50L
const MODULUS: long = 4294967296L
const LOREM: Ascii max 160 = "Lorem {ipsum} dolor {sit} amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore {et} dolore magna aliqua. "

type Page = Bytes max 8000000
type Vars = map<Ascii max 24, Ascii max 16, 200000>

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn first_name(k: long) -> Ascii max 8 {
    match k {
        0L => "John"
        1L => "Jane"
        2L => "Bob"
        3L => "Alice"
        4L => "Charlie"
        5L => "Diana"
        6L => "Sarah"
        _ => "Mike"
    }
}

fn last_name(k: long) -> Ascii max 8 {
    match k {
        0L => "Smith"
        1L => "Johnson"
        2L => "Brown"
        3L => "Taylor"
        4L => "Wilson"
        5L => "Davis"
        6L => "Miller"
        _ => "Jones"
    }
}

fn city(k: long) -> Ascii max 16 {
    match k {
        0L => "New York"
        1L => "Los Angeles"
        2L => "Chicago"
        3L => "Houston"
        4L => "Phoenix"
        _ => "San Francisco"
    }
}

fn put(page: grow Bytes max 8000000, text: Ascii max 160) {
    page.try_append(text.bytes()).unwrap()
}

// Builds the template text and the variable table (LangArena's TemplateBase.prepare).
fn prepare(text: grow Bytes max 8000000, vars: write Vars, count_value: long) {
    put(text, "<html><body>")
    put(text, "<h1>{{TITLE}}</h1>")
    vars.set("TITLE", "Template title").unwrap()
    put(text, "<p>")
    put(text, LOREM)
    put(text, "</p>")
    put(text, "<table>")
    for i: int in 0..(int)count_value {
        if i % 3 == 0 { put(text, "<!-- {comment} -->") }
        put(text, "<tr>")
        put(text, "<td>{{ FIRST_NAME" + str(i) + " }}</td>")
        put(text, "<td>{{LAST_NAME" + str(i) + "}}</td>")
        put(text, "<td>{{  CITY" + str(i) + "  }}</td>")
        vars.set("FIRST_NAME" + str(i), first_name((long)(i % 8))).unwrap()
        vars.set("LAST_NAME" + str(i), last_name((long)(i % 8))).unwrap()
        vars.set("CITY" + str(i), city((long)(i % 6))).unwrap()
        put(text, "<td>{balance: " + str(i % 100) + "}</td>")
        put(text, "</tr>\n")
    }
    put(text, "</table>")
    put(text, "</body></html>")
}

fn is_space(c: long) -> bool { c == 32L || (c >= 9L && c <= 13L) }

fn render(text: Page, vars: Vars, out: grow Bytes max 8000000) {
    let len_value = text.len()
    var i = 0L
    for _step: long in 0L..len_value {
        if i >= len_value { break }
        var copied = true
        if i + 1L < len_value && text[i] == 123 && text[i + 1L] == 123 {
            var j = i + 2L
            for _scan: long in j..len_value {
                if j + 1L >= len_value { break }
                if text[j] == 125 && text[j + 1L] == 125 { break }
                j += 1L
            }
            if j + 1L < len_value {
                // the key between the braces, trimmed
                var from = i + 2L
                var to = j
                for _t: long in from..to {
                    if from < to && is_space(text[from].to_long()) { from += 1L } else { break }
                }
                for _t: long in from..to {
                    if to > from && is_space(text[to - 1L].to_long()) { to -= 1L } else { break }
                }
                var key_bytes: Bytes max 24 = Bytes.empty()
                for k: long in from..to { key_bytes.push(text[k]).unwrap() }
                let key: Ascii max 24 = key_bytes.to_ascii().unwrap()
                match vars.get(key) {
                    some(value) => { out.try_append(value.bytes()).unwrap() },
                    none => {}
                }
                i = j + 2L
                copied = false
            }
        }
        if copied {
            out.push(text[i]).unwrap()
            i += 1L
        }
    }
}

// djb2 over a long byte string, as LangArena's checksum_str (u32).
fn checksum_bytes(text: Page) -> long {
    var hash = 5381L
    for i: long in 0L..text.len() {
        hash = (hash * 33L + text[i].to_long()) % MODULUS
    }
    hash
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let count_value = if run { RUN_COUNT } else { TEST_COUNT }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var text: Page = Bytes.empty()
    var vars: Vars = map {}
    prepare(text, vars, count_value)
    var rendered: Page = Bytes.empty()
    var total = 0L
    for _round: long in 0L..(warmup + iterations) {
        rendered = Bytes.empty()
        render(text, vars, rendered)
        total = (total + rendered.len()) % MODULUS
    }
    print((total + checksum_bytes(rendered)) % MODULUS)
}
