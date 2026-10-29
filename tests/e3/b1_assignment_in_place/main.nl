struct P { x: int, y: int, z: long }
struct Q { p: P, tags: list<int, 4>, grid: int[4] }

fn make(n: int) -> P { P { x: n, y: n + 1, z: 9L } }
fn make_q(n: int) -> Q { Q { p: make(n), tags: [n, n + 1], grid: fill(n) } }
fn bump(q: Q) -> Q {
    var r = q
    r.p.x += 100
    r
}

fn main() {
    var p = P { x: 1, y: 2, z: 3L }
    print(p.x)
    p = make(5)
    print(p.y)
    p = P { x: p.y, y: p.x, z: 4L }
    print(p.x)
    print(p.y)
    var q = make_q(3)
    q = bump(q)
    print(q.p.x)
    q = make_q(7)
    print(q.p.x)
    print(q.tags.count())
    print(q.grid[3])
    var a: P[3] = fill(p)
    a[1].x = 77
    var b = a
    print(b[1].x)
    b = a
    print(b[0].x)
    let c = b[1]
    var d = c
    d = b[2]
    print(d.x)
    for i in 0..2 {
        p = make(i)
        print(p.x)
    }
}
