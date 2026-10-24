struct Holder { inner: map<int, int, 2> }

fn insert(target: write map<int, int, 2>) {
    target.set(1, 10).unwrap()
}

fn main() {
    var outer: map<int, Holder, 2> = map {}
    outer.set(0, Holder { inner: map {} }).unwrap()
    for holder, key in outer { insert(holder.inner) }
}
