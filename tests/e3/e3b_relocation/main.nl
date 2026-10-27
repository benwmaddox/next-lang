struct Wide {
    values: long[513],
}

enum Big {
    Empty,
    Data(Wide),
}

fn fail_after_move(value: write int, payload: Big) -> Result<(), Full> {
    value += 1
    let scratch: list<bool, 300000> = list {}
    let observed = match payload {
        Data(wide) => wide.values[512L]
        Empty => 0L
    }
    print(observed)
    var no_room: list<int, 0> = list {}
    no_room.push(9)?
    value += 100
    ok(())
}

fn last_value(payload: Big) -> long {
    match payload {
        Data(wide) => wide.values[512L]
        Empty => 0L
    }
}

fn main() {
    let payload = Data(Wide { values: fill(7L) })
    var value: int = 4
    print(fail_after_move(value, payload))
    print(value)
    print(last_value(payload))
}
