enum E { A, B, C(int) }
struct Inner { state: E = E.A, maybe: Option<long> = none }
struct Box { a: Option<long>, b: long, inner: Inner = Inner {} }
enum Wrap { Boxed(Box), Choice(E), Maybe(Option<long>) }
fn main() {
    let b1 = Box { a: none, b: 1L }
    print(b1)
    print(Box { a: none, b: 2L, inner: Inner { state: E.A, maybe: none } })
    print(Box { a: none, b: 3L, inner: Inner { state: A, maybe: none } })
    print(Inner {})
    print(Wrap.Boxed(b1))
    print(Wrap.Choice(E.A))
    print(Wrap.Choice(A))
    print(Wrap.Maybe(none))
}
