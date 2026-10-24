enum First { One }
enum Second { Two }
fn source() -> Result<int, First> { ok(1) }
fn target() -> Result<long, Second> {
    let value = source()?
    ok(value.to_long())
}
fn main() { print(target()) }
