enum Color { Red, Blue }
enum Other { Blue }
fn main() {
    let color = Color.Red
    print(match color { Other.Blue => 0, Color.Red => 1, Color.Blue => 2 })
}
