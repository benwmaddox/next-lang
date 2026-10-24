type Small = int 0..=10
fn join(x: int) -> Small {
    var y = x
    if y < 5 { y = 20 }
    y
}
fn main() { print(join(2)) }
