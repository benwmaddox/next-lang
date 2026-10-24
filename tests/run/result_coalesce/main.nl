enum Failure { Bad }
fn main() {
    let value: Result<int, Failure> = ok(1)
    let number = value ?? 0
    print(number)
}
