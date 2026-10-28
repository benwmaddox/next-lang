fn main() {
    var values: list<int, 1> = [5]
    let stop = true
    for index in 0..1 {
        if stop {
            break
        } else {
            values.clear()
        }
    }
    values.push(7)
    print(values)
}
