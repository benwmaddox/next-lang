fn main(env: Env) -> Result<(), IoError> {
    let out = env.out
    let err = env.err
    out.line(b"stdout")?
    err.line(b"stderr")?
    ok(())
}
