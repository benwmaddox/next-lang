fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 4> = list {}
    var total: int = 0
    let source: int[1] = [1]
    relocation_seed()

    if true {
        discard values.push(1)
        for index in 0..1 { total += 1 }
        for value in source { total += value }
        { total += 1 }
    }
    if false {
        discard values.push(20)
    } else if true {
        discard values.push(2)
        for index in 0..1 { total += 1 }
        for value in source { total += value }
        { total += 1 }
    } else {
        discard values.push(21)
    }
    if false {
        discard values.push(30)
    } else {
        discard values.push(3)
        for index in 0..1 { total += 1 }
        for value in source { total += value }
        { total += 1 }
    }
    match true {
        true => {
            discard values.push(4)
            for index in 0..1 { total += 1 }
            for value in source { total += value }
            { total += 1 }
        },
        false => (),
    }
    print(values)
    print(total)
}
