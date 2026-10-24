type Clamp = int 0..=100 clamp
fn main() {
    var value: Clamp = 100
    value += 2147483647
    print(value)
}
