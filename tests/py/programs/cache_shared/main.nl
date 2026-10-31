// Env.cache_put / Env.cache_get: a process-wide cache of byte strings keyed by a long, shared by all jobs.
fn writer(env: Env, base: long) {
    var value: Bytes max 16 = Bytes.empty()
    discard value.push((byte)(65L + base))
    for round in 0L..200L {
        let stored = env.cache_put(base * 1000L + round, value)
    }
}

fn main(env: Env) {
    var out: Bytes max 32 = Bytes.empty()
    print(env.cache_get(7L, out))
    let stored = env.cache_put(7L, "hello")
    print(env.cache_get(7L, out))
    print(out.count())
    print(out[0].to_long())
    // a later put for the same key replaces the value
    let again = env.cache_put(7L, "hi")
    print(env.cache_get(7L, out))
    // a destination that is too small gets nothing
    var tiny: Bytes max 1 = Bytes.empty()
    print(env.cache_get(7L, tiny))
    spawn writer(env, 1L)
    spawn writer(env, 2L)
}
