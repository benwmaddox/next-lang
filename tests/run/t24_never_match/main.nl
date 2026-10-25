fn main(env: Env) -> Result<(), IoError> {
    let first: int = match true {
        true => 1
        false => env.exit(6)
    }
    print(first)
    match false {
        true => env.exit(7)
        false => env.exit(4)
    }
}
