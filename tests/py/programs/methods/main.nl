// `x.m(args)` on a user struct calls Type_m(x, args).
struct Point {
    x: long
    y: long
}

fn Point_sum(p: Point) -> long {
    p.x + p.y
}

fn Point_scaled(p: Point, k: long) -> Point {
    Point { x: p.x * k, y: p.y * k }
}

fn Point_dot(p: Point, q: Point) -> long {
    p.x * q.x + p.y * q.y
}

struct Counter {
    n: long
}

fn Counter_next(c: Counter) -> long {
    c.n + 1L
}

fn main() {
    let p = Point { x: 3L, y: 4L }
    let q = Point { x: 10L, y: 20L }
    print(p.sum())
    print(p.scaled(3L).sum())
    print(p.dot(q))
    print(p.scaled(2L).dot(q.scaled(2L)))
    let c = Counter { n: 41L }
    print(c.next())
    var total = 0L
    for index in 0L..5L {
        total += p.scaled(index).sum()
    }
    print(total)
}
