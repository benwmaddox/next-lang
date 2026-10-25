struct Row { name: Text max 8 }

fn main() {
    var rows: list<Row, 1> = list {}
    discard rows.push(Row { name: "before" })
    for row in rows { row.name = "after" }
}
