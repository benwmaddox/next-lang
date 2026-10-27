fn main() {
    var conditional: list<int, 2> = list {}
    let first = true
    let second = false
    if first {
        discard conditional.push(10)
    } else if second {
        discard conditional.push(20)
    } else {
        discard conditional.push(30)
    }
    discard conditional.push(40)
    print(conditional)

    var matched: list<int, 2> = list {}
    let choice: Option<int> = none
    match choice {
        some(_) => { discard matched.push(1) }
        none => { discard matched.push(2) }
    }
    discard matched.push(3)
    print(matched)

    var cleared_if: list<int, 1> = [5]
    if first {
        cleared_if.clear()
    } else {
        cleared_if.clear()
    }
    discard cleared_if.push(6)
    print(cleared_if)

    var cleared_match: list<int, 1> = [7]
    match choice {
        some(_) => { cleared_match.clear() }
        none => { cleared_match.clear() }
    }
    discard cleared_match.push(8)
    print(cleared_match)

    var looped: list<int, 1> = list {}
    for index in 0..0 { looped.clear() }
    discard looped.push(4)
    print(looped)

    var cleared_loop: list<int, 1> = [11]
    for index in 0..1 { cleared_loop.clear() }
    discard cleared_loop.push(12)
    print(cleared_loop)

    var not_run: list<int, 1> = [9]
    for index in 0..0 {
        not_run.clear()
        not_run.push(10)
    }
    print(not_run)
}
