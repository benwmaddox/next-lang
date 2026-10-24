struct Unit { inventory: list<long, 2> = list {} }
fn main() { var units: Unit[2]; for item in units[0L].inventory { units[0L] = Unit {} } }
