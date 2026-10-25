recursive fn print_at_bottom(n: int) -> int {
    if n == 0 {
        print(0)
        0
    } else {
        print_at_bottom(n - 1) + 1
    }
}

fn main() {
    print(print_at_bottom(1))
}
