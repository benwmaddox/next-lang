// Env.db_rows fills a list<Row, N> from a query that ends with `limit N`; the fields of Row are the columns.
struct Item {
    id: long
    v: long
    name: Bytes max 8
}

fn main(env: Env) {
    var items: list<Item, 5> = list {}
    let count = env.db_rows("from items where room = ?1 order by id limit 5", 2L, items)
    print(count)
    print(items.count())
    var total = 0L
    for item in items { total += item.v }
    print(total)
    print(items[0].name.count())
    print(items[2].id)
    let missing = env.db_rows("from items where room = ?1 order by id limit 5", 9L, items)
    print(missing)
    print(items.count())
}
