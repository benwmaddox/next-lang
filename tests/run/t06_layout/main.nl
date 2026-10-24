struct Point { x: long = 0L, y: long = 0L }
struct Unit { id: long = 0L, inventory: list<Point, 8> = list {} }
fn main() {
    let units: Unit[64]
    for i: long in 0L..units.len() {
        let local: long[2] = fill(i)
        print(units[i].id + local[0L])
    }
}
