fn main() {
    var xs: list<long[3], 4> = list {}
    var a: long[3] = [1L, 2L, 3L]
    var b: long[3] = [10L, 20L, 30L]
    discard xs.push(a)
    discard xs.push(b)
    var total = 0L
    for p in xs {
        total += p[0] + p[2]
    }
    print(total)
    for p in xs {
        print(p[1])
    }
}
