fn main() {
    var q: queue<int, 4> = queue {}
    discard q.push(10)
    discard q.push(20)
    discard q.push(30)
    print(q.count())
    let a = q.pop() ?? -1
    print(a)
    let p = q.peek() ?? -1
    print(p)
    discard q.push(40)
    discard q.push(50)
    print(q.count())
    for i in 0L..5L {
        let v = q.pop() ?? -1
        print(v)
    }
    print(q.count())
}
