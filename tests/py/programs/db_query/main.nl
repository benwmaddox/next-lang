// Env.db_query runs a prepared statement with the key bound to ?1 and returns the first column of the first row.
fn main(env: Env) {
    let missing = env.db_query("select v from t where id = ?1", 99L)
    match env.db_query("select v from t where id = ?1", 7L) {
        some(value) => { print(value) },
        none => { print(-1L) },
    }
    match missing {
        some(value) => { print(value) },
        none => { print(-2L) },
    }
}
