// Readers and writers on the same key: every value read must be whole (all the same letter), never a mix.
fn writer(env: Env, letter: long) {
    var value: Bytes max 400 = Bytes.empty()
    for index in 0L..400L { discard value.push((byte)letter) }
    for round in 0L..200000L {
        let stored = env.cache_put(5L, value)
    }
}

fn reader(env: Env) {
    var out: Bytes max 512 = Bytes.empty()
    var torn = 0L
    var seen = 0L
    for round in 0L..400000L {
        let length = env.cache_get(5L, out)
        if length >= 0L {
            seen += 1L
            let first = out[0].to_long()
            for index in 1L..length {
                if out[index].to_long() != first { torn += 1L; break }
            }
        }
    }
    print(torn)
}

fn main(env: Env) {
    spawn writer(env, 65L)
    spawn writer(env, 66L)
    spawn reader(env)
    spawn reader(env)
}
