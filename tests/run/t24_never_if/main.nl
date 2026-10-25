fn main(env: Env) -> Result<(), IoError> {
    let first: int = if false { env.exit(6) } else { 1 }
    print(first)
    let code: int = if false { 1 } else { env.exit(3) }
    print(code)
    ok(())
}
