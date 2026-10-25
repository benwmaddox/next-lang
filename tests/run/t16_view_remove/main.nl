struct Row { note: Text max 8 }

fn main() {
    var rows: list<Row, 2> = list {}
    discard rows.push(Row { note: "first" })
    for row in rows { discard rows.pop() }
}
