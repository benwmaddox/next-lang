struct Row { name: Ascii max 8 }

fn change(value: write Ascii max 8) { value = "" }

fn main() {
    var rows: list<Row, 1> = list {}
    discard rows.push(Row { name: "before" })
    let updater: fn(write Ascii max 8) = change
    for row in rows { updater(row.name) }
}
