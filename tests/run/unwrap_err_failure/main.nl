enum Failure { Bad }
fn main() {
    let value: Result<int, Failure> = err(Failure.Bad)
    print(value.unwrap())
}
