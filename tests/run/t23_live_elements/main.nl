enum Failure { Bad }

struct Node {
    id: long = 0L,
    values: list<long, 512> = list {},
    spare: list<long, 2> = list {}
}

struct Stored { values: list<long, 4> = list {} }
struct SmallNode { values: list<long, 4> = list {} }

fn numbers(first: long) -> list<long, 4> {
    var values: list<long, 4> = list {}
    discard values.push(first)
    discard values.push(first + 1L)
    values
}

fn wide_numbers(first: long) -> list<long, 512> {
    var values: list<long, 512> = list {}
    discard values.push(first)
    discard values.push(first + 1L)
    values
}

fn identity(values: list<long, 4>) -> list<long, 4> { values }

fn indirect_identity(
    target: fn(list<long, 4>) -> list<long, 4>,
    values: list<long, 4>
) -> list<long, 4> {
    target(values)
}

fn read_node(node: Node) -> long { node.values[0L] }

fn read_small_node(node: SmallNode) -> long { node.values[0L] }

fn write_small_node(node: write SmallNode) {
    discard node.values.push(3L)
}

fn write_node(node: write Node) {
    discard node.values.push(90L)
}

fn write_node_then_fail(node: write Node) -> Option<long> {
    discard node.values.push(91L)
    let absent: Option<long> = none
    let value = absent?
    some(value)
}

fn maybe_values(ready: bool) -> Option<list<long, 4> > {
    if ready { some(numbers(30L)) } else { none }
}

fn maybe_via_callback(
    callback: fn(bool) -> Option<list<long, 4> >,
    ready: bool
) -> Option<list<long, 4> > {
    callback(ready)
}

fn result_node(ready: bool) -> Result<Node, Failure> {
    if ready {
        ok(Node { id: 7L, values: wide_numbers(40L) })
    } else {
        err(Failure.Bad)
    }
}

fn pass_result(value: Result<Node, Failure>) -> Result<Node, Failure> {
    let node = value?
    ok(node)
}

fn first(values: list<long, 4>) -> long { values[0L] }

fn wrap(values: list<long, 4>) -> Option<list<long, 4> > { some(values) }

fn node_before(context: int, left: Node, right: Node) -> bool {
    left.id < right.id
}

fn main() {
    var source: list<long, 4> = numbers(1L)
    source = identity(source)
    print(source)
    source = indirect_identity(identity, source)
    print(source)
    let callback: fn(list<long, 4>) -> list<long, 4> = identity
    source = callback(source)
    print(source)
    source = source

    var small_node: SmallNode = SmallNode { values: numbers(2L) }
    print(read_small_node(small_node))
    write_small_node(small_node)
    print(small_node)
    let small_copy = small_node
    print(small_copy == small_node)

    var nodes: list<Node, 2> = list {}
    discard nodes.push(Node { id: 3L, values: wide_numbers(10L) })
    print(read_node(nodes[0L]))
    write_node(nodes[0L])
    print(nodes[0L])
    let failed_write = write_node_then_fail(nodes[0L])
    print(failed_write)
    print(nodes[0L])
    let copied_nodes = nodes
    discard nodes[0L].values.push(92L)
    print(copied_nodes == nodes)
    print(copied_nodes)

    let default_nodes: Node[2]
    print(default_nodes)
    var board: grid<Node, 2, 1> = fill(Node {})
    discard board[1L, 0L].values.push(20L)
    print(board)

    var inner: list<long, 4> = numbers(21L)
    var nested: list<list<long, 4>, 2> = list {}
    discard nested.push(inner)
    discard inner.push(23L)
    print(nested)
    print(nested[0L] == numbers(21L))

    let present = maybe_values(true)
    let absent = maybe_values(false)
    print(present)
    print(absent)
    let maybe_callback: fn(bool) -> Option<list<long, 4> > = maybe_values
    print(maybe_via_callback(maybe_callback, true))
    print(maybe_via_callback(maybe_callback, false))
    print(present.unwrap())
    print(present ?? list {})
    print(absent ?? numbers(50L))
    match present {
        some(values) => print(values),
        none => print(-1L)
    }
    print(some(numbers(60L))?.first())
    let nested_optional: Option<list<long, 4> > = some(numbers(70L))?.wrap()
    print(nested_optional)
    let nested_variants: Option<Option<list<long, 4> > > = some(some(numbers(71L)))
    print(nested_variants)

    print(result_node(true))
    print(result_node(false))
    print(pass_result(result_node(true)))
    print(pass_result(result_node(false)))
    print(result_node(true).unwrap())

    var by_name: map<Ascii max 20, list<long, 4>, 4> = map {}
    {
        var key: Ascii max 20 = "keep"
        by_name.set(key, numbers(80L)).unwrap()
        key = "gone"
    }
    print(by_name.get("keep"))
    let copied_by_name = by_name
    print(copied_by_name)

    var collisions: map<int, list<long, 4>, 4> = map {}
    collisions.set(1, numbers(1L)).unwrap()
    collisions.set(5, numbers(5L)).unwrap()
    collisions.set(9, numbers(9L)).unwrap()
    collisions.set(13, numbers(13L)).unwrap()
    collisions.remove(5)
    collisions.remove(9)
    let holes = collisions
    print(holes)
    collisions.set(17, numbers(17L)).unwrap()
    collisions.set(21, numbers(21L)).unwrap()
    print(collisions)
    let copied_collisions = collisions
    print(copied_collisions)
    print(collisions.get(21))

    var pool_values: pool<Stored, 2> = pool {}
    let old_id: pool_values.Id = pool_values.add(Stored { values: numbers(100L) }).unwrap()
    print(pool_values.get(old_id))
    pool_values.remove(old_id)
    print(pool_values.get(old_id))
    let new_id: pool_values.Id = pool_values.add(Stored { values: numbers(110L) }).unwrap()
    print(old_id == new_id)
    print(pool_values)
    print(pool_values == pool_values)

    var queue: queue<long, 3> = queue {}
    discard queue.push(1L)
    discard queue.push(2L)
    discard queue.push(3L)
    queue.pop()
    discard queue.push(4L)
    let queue_copy = queue
    queue.pop()
    discard queue.push(5L)
    print(queue)
    print(queue_copy)

    var ring: ring<long, 3> = ring {}
    ring.push(1L)
    ring.push(2L)
    ring.push(3L)
    ring.push(4L)
    let ring_copy = ring
    ring.push(5L)
    print(ring)
    print(ring_copy)

    var sortable: list<Node, 17> = list {}
    for i: long in 0L..15L {
        discard sortable.push(Node { id: 15L - i, values: wide_numbers(i) })
    }
    sort_by(sortable, 0, node_before)
    print(sortable[0L].id)
    print(sortable[14L].values[0L])
    discard sortable.push(Node { id: 0L, values: wide_numbers(0L) })
    sort_by(sortable, 0, node_before)
    print(sortable[0L].id)
    discard sortable.push(Node { id: 16L, values: wide_numbers(16L) })
    sort_by(sortable, 0, node_before)
    sort_by(sortable, 0, node_before)
    print(sortable[0L].id)
    print(sortable[16L].id)
    print(sortable[16L].values[0L])

    {
        var dirty: list<long, 4096> = list {}
        for i: long in 0L..4096L { discard dirty.push(777L + i) }
        print(dirty.count())
    }
    let clean: list<long, 4096> = list {}
    let empty_again: list<long, 4096> = list {}
    print(clean)
    print(clean == empty_again)
    print(clean.count())
}
