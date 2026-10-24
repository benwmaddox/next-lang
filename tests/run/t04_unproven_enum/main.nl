type Small = int 0..=10
enum Value { Small(Small) }
fn main() {
    let input = 20
    print(Value.Small(input))
}
