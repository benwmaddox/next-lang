struct Record {
    name: Bytes max 17,
    id: long,
}

fn main() {
    var values: list<Record, 1> = [Record { name: b"ok", id: 1L }]
    values[0L].name = 7L
}
