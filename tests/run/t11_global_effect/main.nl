global app: int = 0

fn compare(left: int, right: int) -> bool {
    app = 1
    left < right
}

fn use_comparator(callback: fn(int, int) -> bool) -> bool {
    callback(1, 2)
}

fn main() {
    let comparator: fn(int, int) -> bool = compare
    print(use_comparator(comparator))
}
