fn main(env: Env) -> Result<(), IoError> {
    env.out.line("before stdout").unwrap()
    env.err.line("before stderr").unwrap()
    env.exit(2)
}
