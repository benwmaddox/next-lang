type Small = int 0..=10
struct Box { value: Small = 1 }
fn main() {
    let input = 20
    let b = Box { value: input }
    print(b)
}
