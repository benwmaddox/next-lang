enum Color { Red, Blue }
fn main() {
    let color = Color.Red
    print(match color { Color.Red => 1, Red => 2, Blue => 3 })
}
