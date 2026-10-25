fn main(env: Env) -> Result<(), IoError> {
    let ready: Result<(), IoError> = ok(())
    ready?
    env.exit(5)
}
