struct Pair {
    first: Bytes max 8
    second: Bytes max 8
}

fn size_of(a: Bytes max 8, b: Bytes max 8) -> long {
    a.count() * 10L + b.count()
}

fn main() {
    var pairs: list<Pair, 4> = list {}
    var a: Bytes max 8 = Bytes.empty()
    var b: Bytes max 8 = Bytes.empty()
    a.push(1).unwrap()
    pairs.push(Pair { first: a, second: b }).unwrap()
    a.push(2).unwrap()
    b.push(3).unwrap()
    pairs.push(Pair { first: a, second: b }).unwrap()
    a.push(4).unwrap()
    pairs.push(Pair { first: a, second: b }).unwrap()
    for pair in pairs {
        print(size_of(pair.first, pair.second))
    }
}
