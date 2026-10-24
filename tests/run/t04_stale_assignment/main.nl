type Small = int 0..=10
fn unknown() -> int { 20 }
fn stale(x: int) -> Small {
    var y = x
    if y >= 0 && y <= 10 { y = unknown(); y } else { 0 }
}
fn main() { print(stale(5)) }
