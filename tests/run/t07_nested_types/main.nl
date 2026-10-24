struct Nested {
    two: Option<Option<int>>,
    three: Option<Option<Option<int>>>,
    rows: list<list<Option<int>, 4>, 3>,
}

fn pass_two(value: Option<Option<int>>) -> Option<Option<int>> {
    value
}

fn pass_three(value: Option<Option<Option<int>>>) -> Option<Option<Option<int>>> {
    value
}

fn pass_rows(value: list<list<Option<int>, 4>, 3>) -> list<list<Option<int>, 4>, 3> {
    value
}

fn main() {
    let two: Option<Option<int>>=pass_two(some(some(2)))
    let three: Option<Option<Option<int>>> = pass_three(some(some(some(3))))
    var rows: list<list<Option<int>, 4>, 3> = list {}
    let nested = Nested { two, three, rows: pass_rows(rows) }

    print(nested.two.unwrap().unwrap())
    print(nested.three.unwrap().unwrap().unwrap())

    var x = 20
    print(x >> 1)
    x >>= 1
    print(x)
}
