fn fill(q: write queue<int, 8>, n: int) {
    for i in 0L..8L {
        if (int)i < n { discard q.push((int)i * 3) }
    }
}
fn main() {
    var q: queue<int, 8> = queue {}
    fill(q, 5)
    var sum: long = 0L
    for i in 0L..5L { sum += (long)(q.pop() ?? 0) }
    print(sum)
}
