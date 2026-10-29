enum Kind { Ident, Number }

struct Token {
    kind: Kind,
    value: long,
}

struct Tables {
    prefix: long,
    nodes: list<Token, 4>,
}

fn read_kind(tables: write Tables, index: long) -> Kind {
    let kind = tables.nodes[index].kind
    kind
}

fn read_value(tables: write Tables, index: long) -> long {
    tables.nodes[index].value
}

fn token_kind(token: Token) -> Kind {
    token.kind
}

fn read_forwarded(tables: write Tables, index: long) -> Kind {
    token_kind(tables.nodes[index])
}

fn main() {
    var tables = Tables {
        prefix: 77L,
        nodes: [
            Token { kind: Kind.Ident, value: 11L },
            Token { kind: Kind.Number, value: 22L },
        ],
    }
    print(read_kind(tables, 0L) == Kind.Ident)
    print(read_kind(tables, 1L) == Kind.Number)
    print(read_forwarded(tables, 0L) == Kind.Ident)
    print(read_forwarded(tables, 1L) == Kind.Number)
    print(read_value(tables, 0L))
    print(read_value(tables, 1L))
    for token, index in tables.nodes {
        print(index)
        print(token.kind == Kind.Ident)
        print(token.value)
    }
    print(tables.prefix)
}
