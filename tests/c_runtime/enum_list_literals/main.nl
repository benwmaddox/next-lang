enum Color { Red, Green, Blue }
enum Shape { Dot, Circle(int), Rect(int, int) }
struct Pair { c: Color, n: int }

fn count(xs: list<Color, 4>) -> int {
    var n = 0
    for c in xs {
        match c {
            Red => { n += 1 }
            Green => { n += 10 }
            Blue => { n += 100 }
        }
    }
    n
}

fn area(s: Shape) -> int {
    match s {
        Dot => 0
        Circle(r) => r * 3
        Rect(w, h) => w * h
    }
}

fn main() {
    let xs: list<Color, 4> = [Color.Red, Color.Green]
    print(count(xs))
    print(count([Color.Blue, Color.Blue, Color.Red]))
    let ss: list<Shape, 4> = [Shape.Dot, Shape.Circle(2), Shape.Rect(3, 4)]
    var total = 0
    for s in ss {
        total += area(s)
    }
    print(total)
    let arr: Color[3] = [Color.Green, Color.Blue, Color.Red]
    var t = 0
    for c in arr {
        match c {
            Red => { t += 1 }
            Green => { t += 10 }
            Blue => { t += 100 }
        }
    }
    print(t)
    more()
}

struct Team { name: Ascii max 8 = "t", picks: list<Color, 4> = list {} }

fn more() {
    let ps: list<Pair, 3> = [Pair { c: Color.Blue, n: 5 }, Pair { c: Color.Red, n: 6 }]
    var n = 0
    for p in ps {
        n += p.n
        match p.c {
            Blue => { n += 100 }
            Red => { n += 1 }
            Green => { n += 10 }
        }
    }
    print(n)
    let rows: list<list<Color, 2>, 2> = [[Color.Red, Color.Blue], [Color.Green]]
    print(rows[0][1] == Color.Blue)
    let t = Team { name: "ab", picks: [Color.Green, Color.Blue] }
    print(count(t.picks))
    let os: list<Option<Color>, 2> = [some(Color.Red), none]
    var k = 0
    for o in os {
        match o {
            some(c) => { k += 1 }
            none => { k += 10 }
        }
    }
    print(k)
}
