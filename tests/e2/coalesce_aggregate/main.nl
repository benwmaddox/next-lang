struct Pair { value: int }

fn fallback() -> Pair {
    print(99)
    Pair { value: 4 }
}

fn choose(value: Option<Pair>) -> Pair {
    value ?? fallback()
}

fn main() {
    print(choose(some(Pair { value: 3 })))
    print(choose(none))
}
