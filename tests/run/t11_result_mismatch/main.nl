fn answer() -> int { 1 }

fn main() {
    let callback: fn() -> bool = answer
    print(callback())
}
