// Env.db_query runs a prepared statement with the key bound to ?1 and returns the first column of the first row;
// Env.db_text returns that column as text. Mailboxes give their memory back with release().
struct Item {
    v: long
    name: Bytes max 16
    small: int
    flag: bool
}

fn main(env: Env) {
    var item = Item { v: 0L, name: Bytes.empty(), small: 0, flag: false }
    let found = env.db_row("from t where id = ?1", 7L, item)
    print(found)
    print(item.v)
    print(item.name.count())
    print(item.small)
    print(item.flag)
    let missing_row = env.db_row("from t where id = ?1", 99L, item)
    print(missing_row)

    let missing = env.db_query("select v from t where id = ?1", 99L)
    match env.db_query("select v from t where id = ?1", 7L) {
        some(value) => { print(value) },
        none => { print(-1L) },
    }
    match missing {
        some(value) => { print(value) },
        none => { print(-2L) },
    }
    var name: Bytes max 16 = Bytes.empty()
    let length = env.db_text("select name from t where id = ?1", 7L, name)
    print(length)
    print(name.count())
    print(name[0].to_long())
    let none_length = env.db_text("select name from t where id = ?1", 99L, name)
    print(none_length)
    var box: mailbox<long, 4> = mailbox {}
    match box.sender().send(5L) {
        ok(_) => {},
        err(_) => { print(-4L) },
    }
    match box.receiver().recv() {
        some(value) => { print(value) },
        none => { print(-3L) },
    }
    box.release()
}
