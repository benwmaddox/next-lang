// Stage 0 has no generic enums, so a tree node is a struct whose children are
// both `none` for a leaf; leaves are allocated like the reference's `Leaf` boxes.
struct Tree<P> {
    left: Option<Id<P>>
    right: Option<Id<P>>
}

// A depth-d tree has 2^(d+1) - 1 inner nodes plus 2^(d+1) leaves below them.
recursive fn make<P, N>(trees: write pool<Tree<P>, N, P>, d: long) -> Id<P> {
    if d == 0L {
        let left = trees.add(Tree { left: none, right: none }).unwrap()
        let right = trees.add(Tree { left: none, right: none }).unwrap()
        trees.add(Tree { left: some(left), right: some(right) }).unwrap()
    } else {
        let left = make(trees, d - 1L)
        let right = make(trees, d - 1L)
        trees.add(Tree { left: some(left), right: some(right) }).unwrap()
    }
}

recursive fn check<P, N>(trees: pool<Tree<P>, N, P>, id: Id<P>) -> long {
    let node = trees.get(id).unwrap()
    match node.left {
        some(left) => 1L + check(trees, left) + check(trees, node.right.unwrap())
        none => 0L
    }
}

fn main() {
    var acc = 0L
    for _i: long in 0L..1200L {
        var trees: pool<Tree<trees>, 32767> = pool {}
        let root = make(trees, 13L)
        acc += check(trees, root)
    }
    print(acc)
}
