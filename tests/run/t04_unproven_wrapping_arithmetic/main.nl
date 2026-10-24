type Small = int 0..=3
fn add(x: Small) -> Small { x +% 1 }
fn main() { print(add(1)) }
