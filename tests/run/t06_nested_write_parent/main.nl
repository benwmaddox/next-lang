struct Unit { inventory: list<long, 2> = list {} }
fn mutate(units: write list<Unit, 2>) {}
fn main() { var units: list<Unit, 2> = list {}; discard units.push(Unit {}); for item in units[0L].inventory { mutate(units) } }
