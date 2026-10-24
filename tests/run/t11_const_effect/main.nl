fn loud(value: int) -> int {
    print(value)
    value
}

fn invoke(callback: fn(int) -> int effects print, value: int) -> int {
    callback(value)
}

const BAD: int = invoke(loud, 5)

fn main() {
    print(BAD)
}
