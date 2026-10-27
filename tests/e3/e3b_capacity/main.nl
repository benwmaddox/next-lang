fn append(values: write list<int, 1>, value: int) -> Result<(), Full> {
    values.push(value)?
    ok(())
}

fn prepend(values: write list<int, 1>, value: int) -> Result<(), Full> {
    values.insert(0L, value)?
    ok(())
}

fn pop_or_zero(values: write list<int, 1>) -> int {
    values.pop() ?? 0
}

fn pop_with_match(values: write list<int, 1>) -> int {
    match values.pop() {
        some(value) => value,
        none => -1,
    }
}

fn main() {
    var values: list<int, 1> = list {}
    print(append(values, 4))
    print(values)
    print(append(values, 9))
    print(values)
    print(prepend(values, 7))
    print(values)
    print(values.pop())
    print(values.pop())
    print(values)

    var coalesced: list<int, 1> = [6]
    print(pop_or_zero(coalesced))
    print(coalesced)

    var matched: list<int, 1> = [7]
    print(pop_with_match(matched))
    print(pop_with_match(matched))
    print(matched)

    var full: list<int, 0> = list {}
    discard full.push(3)
    print(full)
}
