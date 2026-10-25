fn stop(env: Env, code: int 0..=125) -> never {
    env.exit(code)
}

fn main(env: Env) {
    let callback: fn(Env, int 0..=125) -> int effects env = stop
}
