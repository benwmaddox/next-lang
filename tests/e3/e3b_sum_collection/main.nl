enum Choice { Wrapped(int), Empty }

struct Item {
    choice: Choice,
    maybe: Option<int>,
}

fn main() {
    var choices: list<Choice, 3> = [Wrapped(7), Empty]
    print(choices)
    print(choices.push(Wrapped(9)))
    print(choices)
    let copied: list<Choice, 3> = choices
    print(copied == choices)
    print(choices.pop())
    print(choices.pop())
    print(choices.pop())
    print(choices)

    var items: list<Item, 2> = [Item { choice: Wrapped(11), maybe: some(5) }, Item { choice: Empty, maybe: none }]
    print(items)
    print(items[0L].choice)
    print(items[0L].maybe)
    print(items.pop())
    print(items)
}
