enum First { Red, Other }
enum Second { Red, Maybe }

fn pick(value: First) -> int {
    match value {
        Red => 1
        Other => 2
    }
}

fn main() {
    print(pick(First.Red))
}
