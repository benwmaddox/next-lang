type Small = int 0..=10
fn looped(x: int) -> Small {
    var y = x
    for i in 0..3 { if i == 0 { y = 1 } else { y = y + 1 } }
    y
}
fn main() { print(looped(0)) }
