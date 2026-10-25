struct Row { name: Ascii max 60, count: int 0..=999999 }
struct Payload {
    short: Ascii max 60
    blob: Bytes max 200
    note: Text max 80 bytes max 300
    count: int
}
struct Bucket { notes: list<Text max 8, 2> }

fn line(r: Row) -> Ascii max 80 {
    let name = ascii_upper(r.name)
    name + ": " + str(r.count)
}

fn render(rows: list<Row, 500>) -> Ascii max 40000 {
    var out: Ascii max 40000 = Ascii.empty()
    for r in rows { out += line(r) }
    out
}

fn copy_payloads(source: list<Payload, 2>) -> list<Payload, 2> { source }

fn main() {
    var rows: list<Row, 500> = list {}
    for i in 0..500 {
        discard rows.push(Row { name: "row" + str(i), count: i })
    }
    print(render(rows).len())

    let big_bytes: Bytes max 200 =
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789" + b"0123456789" + b"0123456789" +
        b"0123456789" + b"0123456789"
    let big_text: Text max 80 bytes max 300 =
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀" +
        "😀😀😀😀😀😀😀😀😀😀" + "😀😀😀😀😀😀😀😀😀😀"
    var values: list<Payload, 2> = list {}
    discard values.push(Payload { short: "a", blob: b"small", note: "ok", count: 1 })
    discard values.push(Payload { short: "b", blob: b"small", note: "hey", count: 2 })
    values[0L].short = "inline replacement"
    values[0L].blob = big_bytes
    values[0L].note = big_text
    values[0L].blob = b"tiny"
    values[0L].note = "z"
    print(values[0L].short)
    print(values[0L].blob.len())
    print(values[0L].note.len())
    print(values[1L].short)
    let copied = copy_payloads(values)
    values.clear()
    print(copied[0L].short)
    print(copied[0L].blob.len())
    print(copied[0L].note.len())

    var fixed: Payload[2] = fill(Payload { short: "x", blob: b"y", note: "z", count: 0 })
    fixed[1L] = Payload { short: "array", blob: big_bytes, note: big_text, count: 9 }
    print(fixed[1L].short)
    print(fixed[1L].blob.len())
    print(fixed[1L].note.len())

    var q: queue<Payload, 2> = queue {}
    discard q.push(Payload { short: "q", blob: big_bytes, note: big_text, count: 3 })
    print(q.pop().unwrap().short)
    var ring_values: ring<Payload, 2> = ring {}
    ring_values.push(Payload { short: "r", blob: big_bytes, note: big_text, count: 4 })
    print(ring_values.pop().unwrap().short)

    var matrix: grid<Payload, 2, 1> = fill(Payload { short: "g", blob: b"x", note: "grid", count: 5 })
    matrix[1L, 0L] = Payload { short: "grid row", blob: big_bytes, note: big_text, count: 6 }
    print(matrix[1L, 0L].short)
    print(matrix[1L, 0L].blob.len())

    var mapped: map<Ascii max 8, Payload, 2> = map {}
    mapped.set("first", Payload { short: "m", blob: big_bytes, note: big_text, count: 7 }).unwrap()
    mapped.set("second", Payload { short: "n", blob: b"v", note: "map", count: 8 }).unwrap()
    mapped.set("first", Payload { short: "updated", blob: b"v", note: "up", count: 9 }).unwrap()
    print(mapped.get("first").unwrap().short)
    print(mapped.contains("second"))
    print(mapped.remove("second").is_some())
    print(mapped.count())

    var members: set<Ascii max 8, 2> = set {}
    members.add("one").unwrap()
    members.add("two").unwrap()
    print(members.contains("two"))
    print(members.remove("one"))

    var pool_values: pool<Payload, 2> = pool {}
    let first = pool_values.add(Payload { short: "p", blob: big_bytes, note: big_text, count: 10 }).unwrap()
    let second = pool_values.add(Payload { short: "s", blob: b"z", note: "pool", count: 11 }).unwrap()
    print(pool_values.get(first).unwrap().short)
    print(pool_values.remove(first).is_some())
    let reused = pool_values.add(Payload { short: "reuse", blob: b"again", note: "new", count: 12 }).unwrap()
    print(first == reused)
    print(pool_values.get(second).unwrap().short)

    var buckets: list<Bucket, 2> = list {}
    discard buckets.push(Bucket { notes: list {} })
    discard buckets[0L].notes.push("nested")
    print(buckets[0L].notes[0L])

    var names: list<Ascii max 8, 3> = list {}
    discard names.push("pear")
    discard names.push("apple")
    discard names.push("orange")
    sort(names)
    print(names)
}
