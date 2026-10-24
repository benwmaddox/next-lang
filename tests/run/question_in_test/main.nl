test "no propagation in test" {
    let value: Option<int> = some(1)
    expect value? == 1
}
fn main() {}
