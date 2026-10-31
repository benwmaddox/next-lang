// A string literal can span lines when it is written with three quotes; the line breaks and indentation are part of the text.
struct Item {
    id: long
    name: Bytes max 8
}

fn main(env: Env) {
    let text = """one
  two "quoted" \"escaped\"
three"""
    print(text.len())
    print(text[3])
    print(text[4 + 2])
    var items: list<Item, 5> = list {}
    print(env.db_rows("""
        from items
        where room = ?1
          and id > 1
        order by id
        limit 5
    """, 2L, items))
    print(items[0].id)
}
