type Arena = list<long, 100>
type Count = long
type Counts = list<Count, 10>

fn fill(a: write Arena) {
    for i in 0L..5L { discard a.push(i * i) }
}

fn main() {
    var a: Arena = list {}
    fill(a)
    var c: Counts = list {}
    discard c.push(a[3L])
    print(a[4L] + c[0L])
}
