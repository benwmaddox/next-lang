struct Token { text: Window<src>, kind: long }

fn same(a: Token, b: Token) -> bool {
    a == b
}

fn main(env: Env) {
    var src: arena<100> = arena {}
    let x = src.add("abc")
    let t = Token { text: x, kind: 1L }
    print(same(t, t))
}
