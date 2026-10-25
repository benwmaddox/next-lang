struct Node {
    id: long = 0L,
    values: list<long, 512> = list {},
    spare: list<long, 2> = list {}
}

fn wide_numbers(first: long) -> list<long, 512> {
    var values: list<long, 512> = list {}
    discard values.push(first)
    discard values.push(first + 1L)
    values
}

fn make_node(id: long) -> Node {
    Node { id: id, values: wide_numbers(id) }
}

fn main() {
    var wrapped_queue: queue<Node, 3> = queue {}
    discard wrapped_queue.push(make_node(1L))
    discard wrapped_queue.push(make_node(2L))
    discard wrapped_queue.push(make_node(3L))
    wrapped_queue.pop()
    discard wrapped_queue.push(make_node(4L))
    let queue_copy = wrapped_queue
    wrapped_queue.pop()
    discard wrapped_queue.push(make_node(5L))
    print(wrapped_queue)
    print(queue_copy)

    var empty_queue: queue<Node, 0> = queue {}
    let empty_queue_copy = empty_queue
    print(empty_queue_copy)
    var single_queue: queue<Node, 1> = queue {}
    discard single_queue.push(make_node(1L))
    let single_queue_copy = single_queue
    single_queue.pop()
    discard single_queue.push(make_node(2L))
    print(single_queue)
    print(single_queue_copy)

    var wrapped_ring: ring<Node, 3> = ring {}
    wrapped_ring.push(make_node(1L))
    wrapped_ring.push(make_node(2L))
    wrapped_ring.push(make_node(3L))
    wrapped_ring.push(make_node(4L))
    let ring_copy = wrapped_ring
    wrapped_ring.push(make_node(5L))
    print(wrapped_ring)
    print(ring_copy)

    var empty_ring: ring<Node, 0> = ring {}
    let empty_ring_copy = empty_ring
    print(empty_ring_copy)
    var single_ring: ring<Node, 1> = ring {}
    single_ring.push(make_node(1L))
    let single_ring_copy = single_ring
    single_ring.push(make_node(2L))
    print(single_ring)
    print(single_ring_copy)
}
