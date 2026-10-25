struct Row { note: Bytes max 8 }

fn main() {
    var rows: list<Row, 2> = list {}
    discard rows.push(Row { note: b"first" })
    for row in rows { discard rows.insert(0L, Row { note: b"shift" }) }
}
