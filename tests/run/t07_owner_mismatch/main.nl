struct Rock { value: int }

fn main() {
    var rocks: pool<Rock, 1> = pool {}
    var other: pool<Rock, 1> = pool {}
    let id = rocks.add(Rock { value: 1 }).unwrap()
    let missing = other.get(id)
}
