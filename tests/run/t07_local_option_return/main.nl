struct Rock { value: int }

fn bad<P, N>(source: pool<Rock, N, P>) -> Option<Id<P>> {
    var local: pool<Rock, 1> = pool {}
    some(local.add(Rock { value: 1 }).unwrap())
}

fn main() {
    var rocks: pool<Rock, 1> = pool {}
    let escaped = bad(rocks)
}
