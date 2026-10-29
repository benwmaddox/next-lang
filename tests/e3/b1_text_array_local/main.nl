fn main() {
    let a: (Ascii max 8)[3] = ["a", "bb", "ccc"]
    print(a[0L].len())
    print(a[2L].len())
    print((int)a[1L].bytes()[1L])
}
