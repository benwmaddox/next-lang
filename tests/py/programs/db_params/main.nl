// A struct as the parameters of a query: its fields are bound to ?1, ?2, ... in order (here a text token and a bool).
struct Lookup {
    token: Bytes max 32
    active: bool
}

struct Session {
    user_id: long
}

struct Entry {
    id: long
}

fn main(env: Env) {
    var lookup = Lookup { token: Bytes.empty(), active: true }
    discard lookup.token.try_append("abc123".bytes())
    var session = Session { user_id: 0L }
    print(env.db_row("from sessions where token = ?1 and active = ?2", lookup, session))
    print(session.user_id)
    var entries: list<Entry, 4> = list {}
    print(env.db_rows("from sessions where token = ?1 and active = ?2 order by id limit 4", lookup, entries))
    lookup.active = false
    print(env.db_row("from sessions where token = ?1 and active = ?2", lookup, session))
    var other = Lookup { token: Bytes.empty(), active: true }
    discard other.token.try_append("nope".bytes())
    print(env.db_row("from sessions where token = ?1 and active = ?2", other, session))
}
