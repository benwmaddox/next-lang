fn count(count: int) -> int { count + 1 }
fn item() -> int { 99 }
fn index() -> long { 88L }

struct Count { value: int }

fn show(value: int) { print(value) }

fn main() {
    if true {
        let count = 40
        show(count)
    }
    print(count(4))

    print(8)
    let max = 10
    print(max)
    if true {
        let print = 8
        show(print)
    }

    let Count = 12
    show(Count)

    let items: int[1] = [17]
    for item in items { show(item) }
    for value, index in items {
        show(value)
        print(index)
    }
}
