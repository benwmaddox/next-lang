struct Rock { value: int }
struct Row { rock: pool<Rock, 1> }

fn main() {
    var rows: Row[2] = fill(Row { rock: pool {} })
}
