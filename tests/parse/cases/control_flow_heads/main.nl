struct P { value: int }
const ITEMS: int[1] = [1]
const FLAG: bool = true

fn main() {
    for item in ITEMS {
        print(item)
    }
    for item in (P { value: 1 }).value..=2 {
        print(item)
    }
    if FLAG {
        print(1)
    }
    if (P { value: 1 }).value == 1 {
        print(1)
    }
    match FLAG {
        true => print(1)
        false => print(0)
    }
    match (P { value: 1 }).value {
        1 => print(1)
        _ => print(0)
    }
}
