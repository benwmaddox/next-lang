global items: list<int, 4> = list {}

fn replace_items() {
    items = list {}
}

fn main() {
    for item in items {
        replace_items()
    }
}
