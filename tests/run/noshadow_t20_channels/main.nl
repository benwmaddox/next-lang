fn main(env: Env) -> Result<(), IoError> {
    let out = env.out
    let error_out = env.err
    out.line(b"stdout")?
    error_out.line(b"stderr")?
    ok(())
}
