struct App { items: list<int, 4> }
global app: App = App { items: list {} }

fn clear_items() { app.items.clear() }

fn main() {
    for item in app.items {
        clear_items()
    }
}
