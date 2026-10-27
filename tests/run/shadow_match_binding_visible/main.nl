fn main() {
    let value = 7
    match some(2) {
        some(value) => print(value),
        none => (),
    }
    print(value)
}
