struct Inner { value: int }
struct Outer { inner: Inner, count: int = 0 }

test "struct values copy and compare by fields" {
    var original = Outer { inner: Inner { value: 4 } }
    let copy = original
    expect original == copy
    original.inner.value = 9
    expect original != copy
    expect some(original) == some(original)
}
