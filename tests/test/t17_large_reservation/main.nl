test "a one GiB reservation touches only its live elements" {
    var values: list<long, 125000000> = list {}
    for value: long in 0L..1_000_000L {
        discard values.push(value)
    }
    expect values.count() == 1_000_000L
}

fn main() {
    let values: list<long, 125000000> = list {}
    print(values.count())
}
