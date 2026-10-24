struct Pair { left: int, right: int }
enum Choice { Value(Pair), Empty }
enum Marker { Mark(()) }

fn fold(n: int) -> int {
    var total = 0
    for i in 0..n {
        total += match i { 0 => 1, _ => i }
    }
    total
}

const FORWARD: int = LATER + 1
const LATER: int = 40
const FOLDED: int = fold(3)
const C0: int = fold(0)
const C1: int = fold(1)
const C2: int = fold(2)
const C4: int = fold(4)
const ITEM: Choice = Choice.Value(Pair { left: FORWARD, right: FOLDED })
const PICKED: Choice = if FOLDED == 5 { Choice.Value(Pair { left: 5, right: 1 }) } else { Choice.Empty }
const MAYBE: Option<int> = some(FORWARD)
const NOTHING: Option<int> = none
const ANSWER: Result<int, int> = ok(FOLDED)
const MARKER: Marker = Marker.Mark(())
type Small = int 1..=3
const SMALL: Small = (Small)(3)
const WIDE: long = 5000000000L + 2L
const FLAG: bool = FOLDED == 4

fn main() {
    print(FORWARD)
    print(FOLDED)
    print(ITEM)
    print(PICKED)
    print(MAYBE)
    print(NOTHING)
    print(ANSWER)
    print(MARKER)
    print(SMALL)
    print(WIDE)
    print(FLAG)
    print(fold(0) == C0)
    print(fold(1) == C1)
    print(fold(2) == C2)
    print(fold(4) == C4)
}
