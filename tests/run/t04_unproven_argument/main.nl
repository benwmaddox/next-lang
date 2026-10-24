type Small = int 0..=10
fn need(x: Small) {}
fn forward(x: int) { need(x) }
fn main() { forward(20) }
