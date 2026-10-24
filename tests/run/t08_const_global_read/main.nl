global value: int = 4

fn read_value() -> int { value }

const CACHED: int = read_value()

fn main() {}
