fn fail(env: Env, code: int 0..=125) -> never {
    env.exit(code)
}

fn fail_again(env: Env, code: int 0..=125) -> never {
    fail(env, code)
}

fn accept(value: int) -> int { value }

fn main(env: Env) -> Result<(), IoError> {
    let first: int = if true { 10 } else { accept(fail_again(env, 9)) }
    let second: int = match true {
        true => 20,
        false => accept(fail(env, 8)),
    }
    print(first + second)
    ok(())
}
