fn stop(env: Env, code: int 0..=125) -> never {
    env.exit(code)
}

fn main(env: Env) -> Result<(), IoError> {
    let ready: Result<(), IoError> = ok(())
    ready?
    let callback: fn(Env, int 0..=125) -> never effects env = stop
    callback(env, 7)
}
