struct Rock { value: int }

fn copy_pool<P, N>(source: pool<Rock, N, P>) -> pool<Rock, N, P> {
    source
}

fn main() {
    var rocks: pool<Rock, 1> = pool {}
    let copy = copy_pool(rocks)
}
