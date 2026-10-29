fn main() {
    var c: Counts = list {}
    discard c.push(5L)
    print(c[0L])
}

type Counts = list<Count, 10>
type Count = Id
type Id = long
