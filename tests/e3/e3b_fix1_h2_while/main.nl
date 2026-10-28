fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var total: int = 0
    relocation_seed()
    if true { while total < 1 { total += 1 } }
    if false { } else if true { while total < 2 { total += 1 } }
    if false { } else { while total < 3 { total += 1 } }
    match true {
        true => { while total < 4 { total += 1 } },
        false => (),
    }
    print(total)
}
