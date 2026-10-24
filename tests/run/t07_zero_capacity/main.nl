struct Rock { value: int }

fn main() {
    var empty: pool<Rock, 0> = pool {}
    let full = empty.add(Rock { value: 1 })
    print(full.is_err())
    print(empty.count())
    print(empty)
}
