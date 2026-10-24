type Size = int 1..=3

fn rejected(r: Size) -> Size {
    if r == 2 { return 2 }
    r - 1
}

fn main() { print(rejected(1)) }
