struct Node<P> {
    parent: Option<Id<P>>
    value: int
}

recursive fn fact(n: int) -> int {
    if n <= 1 { 1 } else { n * fact(n - 1) }
}

recursive fn fib(n: int) -> int {
    if n <= 1 { n } else { fib(n - 1) + fib(n - 2) }
}

recursive fn is_even(n: int) -> bool {
    if n == 0 { true } else { is_odd(n - 1) }
}

recursive fn is_odd(n: int) -> bool {
    if n == 0 { false } else { is_even(n - 1) }
}

recursive fn indirect(n: int) -> int {
    if n == 0 {
        0
    } else {
        let callback: fn(int) -> int = indirect
        callback(n - 1) + 1
    }
}

recursive fn depth<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> int {
    let node = nodes.get(id) ?? return 0
    let parent = node.parent ?? return 0
    depth(nodes, parent) + 1
}

recursive fn wide_frame(n: int) -> int {
    var local: int[1024] = fill(n)
    if n == 0 { local[0] } else { wide_frame(n - 1) + local[0] }
}

recursive fn const_sum(n: int) -> int {
    if n == 0 { 0 } else { n + const_sum(n - 1) }
}

recursive fn recursive_less(ctx: int, left: int, right: int) -> bool {
    if ctx == 0 {
        left < right
    } else {
        let callback: fn(int, int, int) -> bool = recursive_less
        callback(ctx - 1, left, right)
    }
}

const SUM: int = const_sum(10)

fn main() {
    print(fact(5))
    print(fib(8))
    print(is_even(12))
    print(is_odd(11))
    print(indirect(8))
    print(wide_frame(3))
    print(SUM)

    var nodes: pool<Node<nodes>, 4> = pool {}
    let root: nodes.Id = nodes.add(Node { parent: none, value: 1 }).unwrap()
    let middle: nodes.Id = nodes.add(Node { parent: some(root), value: 2 }).unwrap()
    let leaf: nodes.Id = nodes.add(Node { parent: some(middle), value: 3 }).unwrap()
    print(depth(nodes, leaf))

    var sortable: list<int, 3> = list {}
    sortable.push(3).unwrap()
    sortable.push(1).unwrap()
    sortable.push(2).unwrap()
    sort_by(sortable, 1, recursive_less)
    print(sortable)
}
