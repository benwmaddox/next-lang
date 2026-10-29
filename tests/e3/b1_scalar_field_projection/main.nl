struct Details {
    code: int,
    active: bool,
}

struct Row {
    name: Bytes max 4096,
    base: long,
    count: int,
    enabled: bool,
    details: Details,
}

fn read_base(rows: list<Row, 4>, index: long) -> long {
    rows[index].base
}

fn read_count(rows: list<Row, 4>, index: long) -> int {
    rows[index].count
}

fn read_enabled(rows: list<Row, 4>, index: long) -> bool {
    rows[index].enabled
}

fn read_nested_code(rows: list<Row, 4>, index: long) -> int {
    rows[index].details.code
}

fn read_nested_active(rows: list<Row, 4>, index: long) -> bool {
    rows[index].details.active
}

fn grow_arena() -> long {
    let frame: list<long, 60000> = [321L]
    frame[0L]
}

fn read_base_after_growth(rows: list<Row, 4>, index: long) -> long {
    let marker = grow_arena()
    rows[index].base + marker - 321L
}

fn next_index(calls: write long) -> long {
    calls = calls + 1L
    1L
}

fn main() {
    var rows: list<Row, 4> = [
        Row {
            name: b"first",
            base: 101L,
            count: 11,
            enabled: true,
            details: Details { code: 111, active: false },
        },
        Row {
            name: b"second",
            base: 202L,
            count: 22,
            enabled: false,
            details: Details { code: 222, active: true },
        },
    ]

    print(rows[0L].base)
    print(read_base(rows, 0L))
    print(read_count(rows, 1L))
    print(read_enabled(rows, 0L))
    print(read_nested_code(rows, 1L))
    print(read_nested_active(rows, 1L))

    print(read_base_after_growth(rows, 1L))
    print(rows[1L].base)
    print(read_count(rows, 1L))
    print(read_enabled(rows, 1L))
    print(read_nested_code(rows, 1L))
    print(read_nested_active(rows, 1L))

    var calls: long = 0L
    print(rows[next_index(calls)].base)
    print(calls)
}
