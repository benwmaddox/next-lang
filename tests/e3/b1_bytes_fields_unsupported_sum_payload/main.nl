enum Name {
    BytesValue(Bytes max 17),
    Empty,
}

struct Record {
    name: Name,
    id: long,
}

fn hold(values: list<Record, 2>) {}

fn main() {}
