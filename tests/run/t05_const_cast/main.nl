type Small = int 1..=3
fn to_small(value: int) -> Small { (Small)(value) }
const BAD: Small = to_small(4)

fn main() { print(BAD) }
