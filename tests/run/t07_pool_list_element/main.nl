struct Rock { value: int }
struct Row { rock: pool<Rock, 1> }

fn main() {
    var rows: list<Row, 2> = list {}
}
