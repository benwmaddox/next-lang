// LangArena Calculator::Ast: generate a program of assignments, then parse it into an AST.
// AST nodes live in one list; children are indices into it (no pointers).
const MAX_TEXT: long = 2097152L     // the generated program (0.5 MB at the run size; 115 bytes per line is the worst case)
const MAX_NODES: long = 400000L
const MAX_LINES: long = 12000L

const EOF: int = 0
const NEWLINE: int = 10

const NUMBER: int = 0
const VARIABLE: int = 1
const BINARY: int = 2
const ASSIGN: int = 3

// One flat node type. NUMBER: value. VARIABLE: name. BINARY: op, left, right.
// ASSIGN: name, left (the expression), value (djb2 hash of the name).
struct Node {
    kind: int
    op: int
    left: int
    right: int
    value: long
    name: Ascii max 16
}

struct Parser {
    pos: long
    len: long
    cur: int
    nodes: list<Node, 400000>
    roots: list<int, 12000>
}

struct Rng { last: long }

fn next_int(rng: write Rng, max_value: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max_value / 139968L
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// ---- program text ----

fn put(out: grow Bytes max 2097152, piece: Bytes max 128) {
    discard out.try_append(piece)
}

fn put_number(out: grow Bytes max 2097152, value: long) {
    var digits: list<int, 20> = list {}
    var rest = value
    for _d in 0L..20L {
        discard digits.push((int)(48L + rest % 10L))
        rest = rest / 10L
        if rest == 0L { break }
    }
    for k in 0L..digits.count() {
        discard out.push(digits[digits.count() - 1L - k])
    }
}

fn put_var(out: grow Bytes max 2097152, index: long) {
    put(out, b"v")
    put_number(out, index)
}

fn generate_program(out: grow Bytes max 2097152, rng: write Rng, n: long) {
    put(out, b"v0 = 1\n")
    for i in 0L..10L {
        let v = i + 1L
        put_var(out, v)
        put(out, b" = ")
        put_var(out, v - 1L)
        put(out, b" + ")
        put_number(out, v)
        put(out, b"\n")
    }
    for i in 0L..n {
        let v = i + 10L
        put_var(out, v)
        put(out, b" = ")
        put_var(out, v - 1L)
        put(out, b" + ")
        let pick = next_int(rng, 10L)
        if pick == 0L {
            put(out, b"(")
            put_var(out, v - 1L)
            put(out, b" / 3) * 4 - ")
            put_number(out, i)
            put(out, b" / (3 + (18 - ")
            put_var(out, v - 2L)
            put(out, b")) % ")
            put_var(out, v - 3L)
            put(out, b" + 2 * ((9 - ")
            put_var(out, v - 6L)
            put(out, b") * (")
            put_var(out, v - 5L)
            put(out, b" + 7))")
        } else if pick == 1L {
            put_var(out, v - 1L)
            put(out, b" + (")
            put_var(out, v - 2L)
            put(out, b" + ")
            put_var(out, v - 3L)
            put(out, b") * ")
            put_var(out, v - 4L)
            put(out, b" - (")
            put_var(out, v - 5L)
            put(out, b" / ")
            put_var(out, v - 6L)
            put(out, b")")
        } else if pick == 2L {
            put(out, b"(3789 - (((")
            put_var(out, v - 7L)
            put(out, b")))) + 1")
        } else if pick == 3L {
            put(out, b"4/2 * (1-3) + ")
            put_var(out, v - 9L)
            put(out, b"/")
            put_var(out, v - 5L)
        } else if pick == 4L {
            put(out, b"1+2+3+4+5+6+")
            put_var(out, v - 1L)
        } else if pick == 5L {
            put(out, b"(99999 / ")
            put_var(out, v - 3L)
            put(out, b")")
        } else if pick == 6L {
            put(out, b"0 + 0 - ")
            put_var(out, v - 8L)
        } else if pick == 7L {
            put(out, b"((((((((((")
            put_var(out, v - 6L)
            put(out, b")))))))))) * 2")
        } else if pick == 8L {
            put_number(out, i)
            put(out, b" * (")
            put_var(out, v - 1L)
            put(out, b"%6)%7")
        } else {
            put(out, b"(1)/(0-")
            put_var(out, v - 5L)
            put(out, b") + (")
            put_var(out, v - 7L)
            put(out, b")")
        }
        put(out, b"\n")
    }
}

// ---- parser ----

fn advance(p: write Parser, input: Bytes max 2097152) {
    p.pos += 1L
    if p.pos >= p.len {
        p.cur = EOF
    } else {
        p.cur = input[p.pos]
    }
}

fn is_digit(byte: int) -> bool { byte >= 48 && byte <= 57 }

fn is_letter(byte: int) -> bool { (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) }

fn is_whitespace(byte: int) -> bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }

fn skip_whitespace(p: write Parser, input: Bytes max 2097152) {
    for _s in 0L..MAX_TEXT {
        if !is_whitespace(p.cur) { break }
        advance(p, input)
    }
}

fn add_node(p: write Parser, node: Node) -> long {
    let id = p.nodes.count()
    discard p.nodes.push(node)
    id
}

fn parse_number(p: write Parser, input: Bytes max 2097152) -> long {
    var value = 0L
    var overflow = false
    for _s in 0L..MAX_TEXT {
        if !is_digit(p.cur) { break }
        let digit = (p.cur - 48).to_long()
        if value > (9223372036854775807L - digit) / 10L { overflow = true } else { value = value * 10L + digit }
        advance(p, input)
    }
    add_node(p, Node { kind: NUMBER, op: 0, left: 0, right: 0, value: if overflow { 0L } else { value }, name: "" })
}

recursive fn parse_variable(p: write Parser, input: Bytes max 2097152) -> long {
    var name: Bytes max 16 = Bytes.empty()
    var hash = 5381L
    for _s in 0L..MAX_TEXT {
        if !(is_letter(p.cur) || is_digit(p.cur)) { break }
        discard name.push(p.cur)
        hash = (hash * 33L + p.cur.to_long()) % 4294967296L
        advance(p, input)
    }
    let text = name.to_ascii().unwrap()
    skip_whitespace(p, input)
    if p.cur == 61 {
        advance(p, input)
        let expr = parse_expression(p, input)
        return add_node(p, Node { kind: ASSIGN, op: 0, left: (int)expr, right: 0, value: hash, name: text })
    }
    add_node(p, Node { kind: VARIABLE, op: 0, left: 0, right: 0, value: 0L, name: text })
}

recursive fn parse_factor(p: write Parser, input: Bytes max 2097152) -> long {
    skip_whitespace(p, input)
    if is_digit(p.cur) {
        parse_number(p, input)
    } else if is_letter(p.cur) {
        parse_variable(p, input)
    } else if p.cur == 40 {
        advance(p, input)
        let node = parse_expression(p, input)
        skip_whitespace(p, input)
        if p.cur == 41 { advance(p, input) }
        node
    } else {
        advance(p, input)
        add_node(p, Node { kind: NUMBER, op: 0, left: 0, right: 0, value: 0L, name: "" })
    }
}

recursive fn parse_term(p: write Parser, input: Bytes max 2097152) -> long {
    var left = parse_factor(p, input)
    for _s in 0L..MAX_TEXT {
        skip_whitespace(p, input)
        if p.cur == 42 || p.cur == 47 || p.cur == 37 {
            let op = p.cur
            advance(p, input)
            let right = parse_factor(p, input)
            left = add_node(p, Node { kind: BINARY, op, left: (int)left, right: (int)right, value: 0L, name: "" })
        } else { break }
    }
    left
}

recursive fn parse_expression(p: write Parser, input: Bytes max 2097152) -> long {
    var left = parse_term(p, input)
    for _s in 0L..MAX_TEXT {
        skip_whitespace(p, input)
        if p.cur == 43 || p.cur == 45 {
            let op = p.cur
            advance(p, input)
            let right = parse_term(p, input)
            left = add_node(p, Node { kind: BINARY, op, left: (int)left, right: (int)right, value: 0L, name: "" })
        } else { break }
    }
    left
}

fn parse(p: write Parser, input: Bytes max 2097152) {
    p.nodes.clear()
    p.roots.clear()
    p.pos = 0L
    p.len = input.count()
    p.cur = EOF
    if p.len > 0L { p.cur = input[0L] }
    for _s in 0L..MAX_LINES {
        if p.cur == EOF { break }
        skip_whitespace(p, input)
        if p.cur == EOF { break }
        let expr = parse_expression(p, input)
        discard p.roots.push((int)expr)
        skip_whitespace(p, input)
        for _n in 0L..MAX_TEXT {
            if p.cur != NEWLINE { break }
            advance(p, input)
            skip_whitespace(p, input)
        }
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let operations = if run { 11000L } else { 3L }
    let iterations = if run { 100L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    // Stage 0 reserves the data stack from one pass down each call chain, not from the recursion
    // depth the parser really reaches, so main sets some room aside (see report).
    let recursion_headroom: Bytes max 262144 = Bytes.empty()
    var rng = Rng { last: 42L }
    var text: Bytes max 2097152 = Bytes.empty()
    generate_program(text, rng, operations)

    var parser = Parser { pos: 0L, len: 0L, cur: EOF, nodes: list {}, roots: list {} }
    var result = 0L
    for _round in 0L..warmup + iterations {
        parse(parser, text)
        result = (result + parser.roots.count()) % 4294967296L
        let last = parser.nodes[parser.roots[parser.roots.count() - 1L].to_long()]
        if last.kind == ASSIGN { result = (result + last.value) % 4294967296L }
    }
    print(result + recursion_headroom.count())
}
