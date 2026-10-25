recursive fn depth(n: long) -> long {
    if n == 0L { 0L } else { 1L + depth(n - 1L) }
}
const X: long = depth(9999L)
fn main() { print(X) }
