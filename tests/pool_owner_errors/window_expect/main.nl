fn main(env: Env) {
    print(1)
}

test "compare windows" {
    var src: arena<100> = arena {}
    let x = src.add("abc")
    let y = src.add("abc")
    expect x == y
}
