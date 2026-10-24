struct Inner { value: int, other: int }
struct Outer { inner: Inner }
fn pair(a: write int, b: Inner) {}
fn main() { var o = Outer { inner: Inner { value: 1, other: 2 } }; pair(o.inner.value, o.inner) }
