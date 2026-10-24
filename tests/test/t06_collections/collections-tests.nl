test "collection equality compares active elements and evaluates once" {
    var stale: list<long, 3> = list {}
    discard stale.push(1L)
    discard stale.push(2L)
    print(stale.pop())
    var short: list<long, 3> = list {}
    discard short.push(1L)
    expect stale == short
    expect make_list() == VALUES
    expect left() == right()
    let first: long[2] = fill(7L)
    let second: long[2] = fill(7L)
    expect first == second
    expect GRID == second
}
