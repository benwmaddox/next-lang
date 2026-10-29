enum Kind { Ident, Number }

struct Token {
    kind: Kind,
    value: long,
}

fn peek(value: long) -> Token {
    print(value)
    if value == 0L {
        Token { kind: Kind.Ident, value: value }
    } else {
        Token { kind: Kind.Number, value: value }
    }
}

fn accepts(kind: Kind, value: long) -> bool {
    peek(value).kind == kind
}

fn main() {
    print(accepts(Kind.Ident, 0L))
    print(accepts(Kind.Number, 0L))
    print(accepts(Kind.Number, 1L))
    print(accepts(Kind.Ident, 1L))
}
