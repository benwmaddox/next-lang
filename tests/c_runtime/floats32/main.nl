fn avg(a: float, b: float) -> float {
    (a + b) / 2.0
}

struct Point { x: float, y: float }

fn main() {
    let x: float = 1.5
    let y = x * 2.0 + 0.25
    print((long)(y * 1000.0))
    print((long)(avg(3.0, 4.0) * 10.0))
    var s: float = 0.0
    for i in 0L..10L { s += (float)i * 0.5 }
    print((long)(s * 2.0))
    print(x < y)
    print(-x == -1.5)
    let n = 7
    print((long)((float)n / 2.0 * 100.0))
    var p = Point { x: 0.5, y: 0.25 }
    p.x += p.y
    print((long)(p.x * 100.0))
    var values: list<float, 4> = list {}
    values.push(2.5).unwrap()
    values.push(0.125).unwrap()
    print((long)((values[0L] + values[1L]) * 1000.0))
    // float is 32 bits: 0.1 as a float widened to double is not 0.1
    let tenth: float = 0.1
    let wide = (double)tenth
    print(wide == 0.1)
    print((float)wide == tenth)
    print((int)(tenth * 1000000.0))
    let big: float = 3000000000.0
    print((long)big)
    let back = (float)(double)2.5
    print((long)(back * 2.0))
    print(1.0 / 3.0 > 0.3)
}
