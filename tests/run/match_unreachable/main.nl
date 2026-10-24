enum Color { Red, Blue }
fn main() {
    let c = Color.Red
    print(match c { _ => 0, Color.Red => 1 })
}
