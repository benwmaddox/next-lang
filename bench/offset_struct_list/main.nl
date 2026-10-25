struct Pair { x: long, y: long }

fn main() {
    var pairs: list<Pair, 8192> = list {}
    for index: long in 0L..8192L {
        discard pairs.push(Pair { x: index + 1L, y: index * 3L })
    }

    var reserve: list<long, 20000> = list {}
    print(reserve.count())

    var checksum = 0L
    for round: long in 0L..2048L {
        var pass = 0L
        for index: long in 0L..8192L {
            pass += pairs[index].y
            pairs[index].x += 1L
        }
        checksum += pass
    }

    print(checksum)
    print(pairs[0L].x)
    print(pairs[8191L].y)
}
