struct Inner { value: int }
struct Outer { inner: Inner }
fn main() { let o = Outer { inner: Inner {} }; print(o) }
