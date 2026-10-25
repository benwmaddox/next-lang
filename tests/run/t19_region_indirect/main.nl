recursive fn walk(n: int) -> int {
    var scratch: int[2048] = fill(n)
    if n == 0 {
        scratch[0]
    } else {
        let callback: fn(int) -> int = walk
        callback(n - 1) + scratch[0]
    }
}

fn main() {
    print(walk(2))
}
