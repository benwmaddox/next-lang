struct App { items: list<int, 4> }
global app: App = App { items: list {} }

fn read_items() -> long { app.items.count() }

fn helper(items: write list<int, 4>) {
    print(read_items())
}

fn main() {
    helper(app.items)
}
