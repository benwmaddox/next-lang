fn main() {
    var values: list<int, 3> = [1]
    for value in values {
        { value += 1 }
        print(value)
        discard values.push(2)
    }
    print(values)
    values.clear()
    print(values)
}
