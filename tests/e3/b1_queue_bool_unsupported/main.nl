fn main() {
    var q: queue<bool, 4> = queue {}
    discard q.push(true)
    print(q.count())
}
