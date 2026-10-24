struct Ops {
    run: fn() -> int
}

fn run() -> int { 1 }

fn main() {
    let ops = Ops {}
    print(ops.run())
}
