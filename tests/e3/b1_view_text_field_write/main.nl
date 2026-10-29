struct Row { name: Ascii max 8 }
fn main() {
    var rows: list<Row, 1> = list {}
    discard rows.push(Row { name: "before" })
    for row in rows { row.name = "after" }
    print(rows[0L].name.len())
}
