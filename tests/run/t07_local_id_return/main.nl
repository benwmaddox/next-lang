struct Rock { value: int }

fn bad<P, N>(source: pool<Rock, N, P>) -> Id<P> {
    var local: pool<Rock, 1> = pool {}
    local.add(Rock { value: 1 }).unwrap()
}

fn main() {
    var rocks: pool<Rock, 1> = pool {}
    let escaped = bad(rocks)
}
