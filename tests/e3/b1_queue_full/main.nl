fn main() {
    var q: queue<long, 3> = queue {}
    var accepted: long = 0L
    var refused: long = 0L
    for i in 0L..6L {
        match q.push(i * 100L) {
            ok(_) => { accepted += 1L }
            err(_) => { refused += 1L }
        }
    }
    print(accepted)
    print(refused)
    print(q.pop() ?? 0L)
    print(q.pop() ?? 0L)
    print(q.pop() ?? 0L)
    print(q.pop() ?? 99L)
}
