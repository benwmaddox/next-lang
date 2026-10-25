fn main() {
    let value: Result<int, int> = err(0)
    match value {
        some(_) => {},
        ok(_) => {},
        err(_) => {}
    }
}
