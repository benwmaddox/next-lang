fn scale(value: int, factor: int) -> int {
    value * factor
}

fn maybe_add(value: int, increment: int) -> Option<int> {
    if value > 0 { some(value + increment) } else { none }
}

fn effect() -> int {
    print(99)
    3
}

fn main() {
    let absent: Option<int> = none
    let present: Option<int> = some(4)
    print(absent?.scale(effect()))
    print(present?.scale(effect()))
    print(absent?.maybe_add(2))
    print(present?.maybe_add(2))
    print(present?.to_long())
    print(absent?.maybe_add(2)?.to_long())
    print(present?.maybe_add(2)?.to_long())
}
