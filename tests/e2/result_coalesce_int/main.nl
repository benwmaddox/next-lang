enum Failure { Bad }
fn result_coalesce(value: Result<int, Failure>) -> int {
    value ?? 1
}
fn main() {
    print(result_coalesce(ok(1)))
}
