fn get() -> Option<int> { some(1) }
fn bad() -> int { get()? }
fn main() { print(bad()) }
