struct Inner { value: int, other: int }
struct Outer { inner: Inner }
fn pair(a: Inner, b: write int) {}
fn main() { var o = Outer { inner: Inner { value: 1, other: 2 } }; pair(o.inner, o.inner.value) }
