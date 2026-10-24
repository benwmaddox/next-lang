struct App { items: list<int, 4>, score: int }
global app: App = App { items: list {}, score: 0 }

fn main() {
    for item in app.items {
        app.score += 1
    }
    print(app.score)
}
