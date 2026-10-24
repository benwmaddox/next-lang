fn main() {
    var q: queue<long, 2> = queue {}
    discard q.push(1L)
    for item in q {
        discard q.pop()
    }
}
