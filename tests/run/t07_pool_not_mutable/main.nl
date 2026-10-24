struct Rock { value: int }

fn main() {
    let rocks: pool<Rock, 1> = pool {}
    let id = rocks.add(Rock { value: 1 })
}
