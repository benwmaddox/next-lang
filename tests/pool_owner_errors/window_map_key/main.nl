fn main(env: Env) {
    var src: arena<100> = arena {}
    let x = src.add("abc")
    var m: map<Window<src>, long, 8> = map {}
    match m.set(x, 1L) { ok(_) => (), err(_) => () }
}
