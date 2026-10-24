type Small = int 0..=10
struct Bad { value: Small = 20 }
fn main() { let b = Bad {}; print(b) }
