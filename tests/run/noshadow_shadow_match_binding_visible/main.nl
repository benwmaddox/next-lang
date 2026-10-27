fn main() {
    let value = 7
    match some(2) {
        some(inner_value) => print(inner_value),
        none => (),
    }
    print(value)
}
