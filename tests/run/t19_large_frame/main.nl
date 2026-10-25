recursive fn frame(n: int) -> int {
    var values: int[1024] = fill(n)
    sort(values)
    if n == 0 { values[0] } else { frame(n - 1) + values[0] }
}

fn main() {
    print(frame(100))
}
