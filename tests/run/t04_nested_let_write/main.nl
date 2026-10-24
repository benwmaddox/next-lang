struct Inner { value: int }
struct Outer { inner: Inner }
fn main() { let o = Outer { inner: Inner { value: 1 } }; o.inner.value = 2 }
