fn grower(values: write list<long, 128>) {
    let scratch: list<long, 100000> = list {}
    print(scratch.count())
    values[0] += 1L
}

fn main() {
    var values: list<long, 128> = list {}
    discard values.push(1L)
    var until_grow = 0

    for index in 0..12 {
        if until_grow == 0 {
            grower(values)
            until_grow = 3
        } else {
            until_grow -= 1
        }

        let observed = values[0]
        values[0] += observed + 1L
    }

    print(values[0])
}
