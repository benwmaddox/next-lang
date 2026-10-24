fn fails() -> bool { 1 / 0 == 0 }
fn main() {
    print(false && fails())
    print(true || fails())
}
