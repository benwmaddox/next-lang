struct S { value: int = caller }

fn main() {
    let caller = 7
    let value = S {}
    print(value.value)
}
