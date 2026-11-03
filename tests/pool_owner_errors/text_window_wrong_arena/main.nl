fn main(env: Env) {
    var a: arena<100> = arena {}
    var b: arena<100> = arena {}
    let w = a.add("hello")
    let v = b.add("hello")
    print(w == v)
}
