fn avg(a: double, b: double) -> double {
    (a + b) / 2.0
}

struct Point { x: double, y: double }

fn main() {
    let x = 1.5
    let y = x * 2.0 + 0.25
    print((long)(y * 1000.0))
    print((long)(avg(3.0, 4.0) * 10.0))
    var s = 0.0
    for i in 0L..10L { s += (double)i * 0.5 }
    print((long)(s * 2.0))
    print(x < y)
    print(-x == -1.5)
    let n = 7
    print((long)(n.to_double() / 2.0 * 100.0))
    var p = Point { x: 0.1, y: 0.2 }
    p.x += p.y
    print((long)(p.x * 10000000000.0))
    var values: list<double, 4> = list {}
    values.push(2.5).unwrap()
    values.push(0.125).unwrap()
    print((long)(values[0L] + values[1L]) * 1000)
    print(str_fixed(3.14159, 3))
    print(str_fixed(0.5, 10))
    match "2.5".parse_double() {
        some(v) => print((long)(v * 10.0)),
        none => print(-1)
    }
    match "abc".parse_double() {
        some(v) => print((long)(v * 10.0)),
        none => print(-1)
    }
}
