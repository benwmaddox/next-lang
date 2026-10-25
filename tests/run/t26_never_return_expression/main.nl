fn fail() -> never {
    let value: int = if true { return } else { 1 }
}

fn main() {}
