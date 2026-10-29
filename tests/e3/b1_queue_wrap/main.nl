fn main() {
    var q: queue<int, 5> = queue {}
    var checksum: long = 0L
    var next: int = 1
    for round in 0L..200L {
        discard q.push(next)
        next += 1
        discard q.push(next)
        next += 1
        let a = q.pop() ?? 0
        checksum = (checksum * 31L + (long)a) % 1000003L
        if q.count() > 3L {
            let b = q.pop() ?? 0
            checksum = (checksum * 17L + (long)b) % 1000003L
        }
    }
    print(checksum)
    print(q.count())
}
