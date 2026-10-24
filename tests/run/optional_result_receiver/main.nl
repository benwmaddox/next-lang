enum Failure { Bad }
fn plus(value: int) -> int { value + 1 }
fn main() {
    let value: Result<int, Failure> = ok(1)
    print(value?.plus())
}
