enum Kind { Ident, Number }
enum Payload { Whole(long), Small(int) }

struct Row {
    kind: Kind,
    marker: long,
    payload: Payload,
    maybe: Option<long>,
    result: Result<long, int>,
}

fn accepts(kind: Kind) -> bool {
    kind == Kind.Number
}

fn forward(kind: Kind) -> bool {
    accepts(kind)
}

fn grow_arena() -> long {
    let frame: list<long, 60000> = [123L]
    frame[0L]
}

fn assign_kind(value: write Kind, kind: Kind) {
    value = kind
}

fn forward_assign_kind(value: write Kind, kind: Kind) {
    assign_kind(value, kind)
}

fn assign_kind_after_growth(value: write Kind, kind: Kind) {
    let marker = grow_arena()
    if marker == 123L { value = kind }
}

fn accepts_after_growth(kind: Kind) -> bool {
    let marker = grow_arena()
    kind == Kind.Number && marker == 123L
}

fn assign_payload(value: write Payload, payload: Payload) {
    value = payload
}

fn payload_value(value: Payload) -> long {
    match value {
        Payload.Whole(number) => number,
        Payload.Small(number) => number.to_long(),
    }
}

fn forward_payload(value: Payload) -> long {
    payload_value(value)
}

fn maybe_value(value: Option<long>) -> long {
    match value {
        some(number) => number,
        none => -1L,
    }
}

fn forward_maybe(value: Option<long>) -> long {
    maybe_value(value)
}

fn result_value(value: Result<long, int>) -> long {
    match value {
        ok(number) => number,
        err(number) => number.to_long(),
    }
}

fn forward_result(value: Result<long, int>) -> long {
    result_value(value)
}

fn set_row(values: write list<Row, 128>, index: long, kind: Kind, marker: long) {
    values[index].kind = kind
    values[index].marker = marker
}

fn forward_set_row(values: write list<Row, 128>, index: long, kind: Kind, marker: long) {
    set_row(values, index, kind, marker)
}

fn main() {
    var rows: list<Row, 128> = [
        Row { kind: Kind.Ident, marker: 101L, payload: Payload.Whole(111L), maybe: some(121L), result: ok(131L) },
        Row { kind: Kind.Number, marker: 202L, payload: Payload.Small(22), maybe: none, result: err(23) },
    ]

    print(accepts(rows[0L].kind))
    print(accepts(rows[1L].kind))
    print(forward(rows[0L].kind))
    print(forward(rows[1L].kind))
    print(accepts_after_growth(rows[0L].kind))
    print(accepts_after_growth(rows[1L].kind))
    print(payload_value(rows[0L].payload))
    print(payload_value(rows[1L].payload))
    print(forward_payload(rows[0L].payload))
    print(forward_payload(rows[1L].payload))
    print(maybe_value(rows[0L].maybe))
    print(maybe_value(rows[1L].maybe))
    print(forward_maybe(rows[0L].maybe))
    print(forward_maybe(rows[1L].maybe))
    print(result_value(rows[0L].result))
    print(result_value(rows[1L].result))
    print(forward_result(rows[0L].result))
    print(forward_result(rows[1L].result))

    assign_kind(rows[1L].kind, Kind.Ident)
    print(rows[1L].kind == Kind.Ident)
    forward_assign_kind(rows[1L].kind, Kind.Number)
    print(rows[0L].kind == Kind.Ident)
    print(rows[1L].kind == Kind.Number)
    print(rows[0L].marker)
    print(rows[1L].marker)

    assign_payload(rows[1L].payload, Payload.Whole(555L))
    print(payload_value(rows[0L].payload))
    print(payload_value(rows[1L].payload))

    assign_kind_after_growth(rows[1L].kind, Kind.Ident)
    print(rows[0L].kind == Kind.Ident)
    print(rows[1L].kind == Kind.Ident)
    print(rows[0L].marker)
    print(rows[1L].marker)

    forward_set_row(rows, 1L, Kind.Ident, 909L)
    print(rows[0L].kind == Kind.Ident)
    print(rows[1L].kind == Kind.Ident)
    print(rows[0L].marker)
    print(rows[1L].marker)
}
