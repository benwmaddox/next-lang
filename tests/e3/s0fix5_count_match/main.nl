fn main() {
    var values: list<int, 1> = [5]
    let choice: Option<int> = none
    match choice {
        some(value) => values.clear(),
        none => (),
    }
    values.push(7)
    print(values)
}
