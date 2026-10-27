struct Rock { value: int }

fn main() {
    var empty_pool: pool<Rock, 0> = pool {}
    let full = empty_pool.add(Rock { value: 1 })
    print(full.is_err())
    print(empty_pool.count())
    print(empty_pool)
}
