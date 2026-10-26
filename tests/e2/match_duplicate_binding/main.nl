enum Pair { Values(int, int), Empty }
fn main() {
    let result = match Pair.Values(1, 2) { Values(value, value) => value, Empty => 0 }
    print(result)
}
