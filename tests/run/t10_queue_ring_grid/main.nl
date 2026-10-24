struct Cell { value: long = 0L, tag: int = 0 }
struct Board {
    queue: queue<Cell, 2> = queue {}
    ring: ring<Cell, 2> = ring {}
    grid: grid<Cell, 2, 2> = fill(Cell {})
}
struct World { boards: Board[2] }

fn bump(calls: write int) -> long {
    calls += 1
    calls.to_long()
}

fn make_queue() -> queue<long, 3> {
    var q: queue<long, 3> = queue {}
    discard q.push(11L)
    discard q.push(22L)
    q
}

fn make_grid() -> grid<long, 2, 2> {
    var g: grid<long, 2, 2> = fill(0L)
    g[0L, 0L] = 1L
    g[1L, 0L] = 2L
    g[0L, 1L] = 3L
    g[1L, 1L] = 4L
    g
}

fn set_grid(g: write grid<long, 2, 2>, x: long, y: long) {
    g[x, y] = 99L
}

const SAVED_QUEUE: queue<long, 3> = make_queue()
const SAVED_GRID: grid<long, 2, 2> = make_grid()

fn main() {
    var calls = 0
    var q: queue<long, 3> = queue {}
    print(q.peek())
    print(q.pop())
    print(q.push(1L))
    print(q.push(2L))
    print(q.push(3L))
    print(q.push(4L))
    print(q)
    print(q.peek())
    print(q.pop())
    discard q.push(4L)
    print(q)
    for item, index in q {
        print(item)
    }

    var growing: queue<long, 4> = queue {}
    discard growing.push(10L)
    discard growing.push(20L)
    for item, index in growing {
        print(item)
        if index == 0L { discard growing.push(30L) }
    }
    print(growing)

    var first_queue: queue<long, 3> = queue {}
    discard first_queue.push(1L)
    discard first_queue.push(2L)
    first_queue.pop()
    discard first_queue.push(3L)
    var second_queue: queue<long, 3> = queue {}
    discard second_queue.push(2L)
    discard second_queue.push(3L)
    print(first_queue == second_queue)

    var r: ring<long, 3> = ring {}
    r.push(1L)
    r.push(2L)
    r.push(3L)
    r.push(4L)
    r.push(5L)
    r.push(6L)
    print(r)
    print(r.peek())
    print(r.pop())
    r.push(7L)
    r.push(8L)
    print(r)
    print(r.count())
    for item, index in r { print(item) }
    var first_layout: ring<long, 3> = ring {}
    first_layout.push(1L)
    first_layout.push(2L)
    first_layout.push(3L)
    first_layout.push(4L)
    var second_layout: ring<long, 3> = ring {}
    second_layout.push(2L)
    second_layout.push(3L)
    second_layout.push(4L)
    print(first_layout == second_layout)
    var append_ring: ring<long, 3> = ring {}
    append_ring.push(1L)
    for item in append_ring { append_ring.push(2L) }
    print(append_ring)
    var zero_queue: queue<long, 0> = queue {}
    print(zero_queue.push(9L))
    print(zero_queue.count())
    var zero_ring: ring<long, 0> = ring {}
    zero_ring.push(bump(calls))
    print(zero_ring.count())
    print(zero_ring)

    var filled: grid<long, 2, 2> = fill(bump(calls))
    print(calls)
    print(filled)
    var no_cells: grid<long, 0, 2> = fill(bump(calls))
    print(calls)
    print(no_cells)
    print(no_cells.width())
    print(no_cells.height())
    let defaults: grid<long, 1, 2>
    print(defaults)
    var g: grid<long, 2, 2> = fill(0L)
    g[0L, 0L] = 1L
    g[1L, 0L] = 2L
    g[0L, 1L] = 3L
    g[1L, 1L] = 4L
    print(g.width())
    print(g.height())
    print(g[1L, 0L])
    set_grid(g, 1L, 1L)
    print(g)
    for cell, x, y in g {
        print(cell)
        print(x)
        print(y)
    }

    print(SAVED_QUEUE)
    print(make_queue() == SAVED_QUEUE)
    print(SAVED_GRID)
    print(make_grid() == SAVED_GRID)

    let world: World
    print(world.boards[1L].grid)
}
