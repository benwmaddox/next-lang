// LangArena Maze::AStar: A* (Manhattan heuristic) from the start to the finish.
// Cells are indices y * width + x; each interior cell has 4 neighbours in a shuffled order
// (the shuffle consumes the shared random sequence once, when the maze is created).
const MAX_CELLS: long = 1960000L        // 1400 x 1400, the run size
const MAX_NEIGHBORS: long = 7840000L    // 4 per cell, also the bound on dig's stack pushes

const WALL: int = 0
const SPACE: int = 1
const START: int = 2
const FINISH: int = 3
const BORDER: int = 4

struct Rng { last: long }

struct Maze {
    width: long
    height: long
    kind: int[1960000]
    neighbors: int[7840000]    // 4 cell indices per cell
}

fn next_int(rng: write Rng, max_value: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max_value / 139968L
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn is_walkable(kind: int) -> bool {
    kind == SPACE || kind == START || kind == FINISH
}

fn finish_cell(maze: Maze) -> long {
    (maze.height - 2L) * maze.width + maze.width - 2L
}

fn link_neighbors(maze: write Maze, rng: write Rng) {
    let w = maze.width
    let h = maze.height
    for y in 0L..h {
        for x in 0L..w {
            let cell = y * w + x
            if x == 0L || y == 0L || x == w - 1L || y == h - 1L {
                maze.kind[cell] = BORDER
            } else {
                var order: int[4] = fill(0)
                order[0L] = (int)(cell - w)
                order[1L] = (int)(cell + w)
                order[2L] = (int)(cell + 1L)
                order[3L] = (int)(cell - 1L)
                for _k in 0L..4L {
                    let i = next_int(rng, 4L)
                    let j = next_int(rng, 4L)
                    if i != j {
                        let held = order[i]
                        order[i] = order[j]
                        order[j] = held
                    }
                }
                for k in 0L..4L { maze.neighbors[cell * 4L + k] = order[k] }
            }
        }
    }
    maze.kind[w + 1L] = START
    maze.kind[finish_cell(maze)] = FINISH
}

fn walkable_neighbors(maze: Maze, cell: long) -> long {
    var found = 0L
    for k in 0L..4L {
        if is_walkable(maze.kind[maze.neighbors[cell * 4L + k].to_long()]) { found += 1L }
    }
    found
}

fn dig(maze: write Maze, first: long) {
    var stack: list<int, 8000000> = list {}
    discard stack.push((int)first)
    for _step in 0L..MAX_NEIGHBORS + 1L {
        let cell = (stack.pop() ?? break).to_long()
        if walkable_neighbors(maze, cell) == 1L {
            maze.kind[cell] = SPACE
            for k in 0L..4L {
                let neighbor = maze.neighbors[cell * 4L + k]
                if maze.kind[neighbor.to_long()] == WALL {
                    discard stack.push(neighbor)
                }
            }
        }
    }
}

recursive fn ensure_open_finish(maze: write Maze, cell: long) {
    maze.kind[cell] = SPACE
    var walls: list<int, 4> = list {}
    for k in 0L..4L {
        let neighbor = maze.neighbors[cell * 4L + k]
        if maze.kind[neighbor.to_long()] == WALL { discard walls.push(neighbor) }
    }
    if walkable_neighbors(maze, cell) > 1L { return }
    for wall in walls { ensure_open_finish(maze, wall.to_long()) }
}

fn generate(maze: write Maze) {
    let first = maze.width + 1L
    for k in 0L..4L {
        let neighbor = maze.neighbors[first * 4L + k]
        if maze.kind[neighbor.to_long()] == WALL { dig(maze, neighbor.to_long()) }
    }
    let finish = finish_cell(maze)
    for k in 0L..4L {
        let neighbor = maze.neighbors[finish * 4L + k]
        if maze.kind[neighbor.to_long()] == WALL { ensure_open_finish(maze, neighbor.to_long()) }
    }
}

fn new_maze(width_value: long, height: long, rng: write Rng) -> Maze {
    var maze = Maze { width: width_value, height, kind: fill(WALL), neighbors: fill(0) }
    link_neighbors(maze, rng)
    maze
}

struct PathInfo {
    length: long
    mid: long    // x * y of the path's middle cell
}

fn mid_product(maze: Maze, cell: long) -> long {
    (cell / maze.width) * (cell % maze.width)
}

// Min-heap of (f, cell) pairs packed as f * 2^21 + cell, ordered like the reference's tuples.
fn heap_push(heap: write list<long, 8000000>, key: long) {
    discard heap.push(key)
    var i = heap.count() - 1L
    for _up in 0L..64L {
        if i == 0L { break }
        let parent = (i - 1L) / 2L
        if heap[parent] <= heap[i] { break }
        let held = heap[parent]
        heap[parent] = heap[i]
        heap[i] = held
        i = parent
    }
}

fn heap_pop(heap: write list<long, 8000000>) -> long {
    let top = heap[0L]
    let last = heap.pop() ?? top
    let n = heap.count()
    if n > 0L {
        heap[0L] = last
        var i = 0L
        for _down in 0L..64L {
            let left = 2L * i + 1L
            if left >= n { break }
            var child = left
            if left + 1L < n && heap[left + 1L] < heap[left] { child = left + 1L }
            if heap[i] <= heap[child] { break }
            let held = heap[child]
            heap[child] = heap[i]
            heap[i] = held
            i = child
        }
    }
    top
}

fn heuristic(maze: Maze, a: long, b: long) -> int {
    let dy = a / maze.width - b / maze.width
    let dx = a % maze.width - b % maze.width
    (int)(abs(dy) + abs(dx))
}

fn astar(maze: Maze, source: long, target: long) -> PathInfo {
    let none_found = PathInfo { length: 0L, mid: 0L }
    if source == target { return PathInfo { length: 1L, mid: mid_product(maze, source) } }
    var came_from: int[1960000] = fill(-1)
    var g_score: int[1960000] = fill(2147483647)
    var best_f: int[1960000] = fill(2147483647)
    var open_set: list<long, 8000000> = list {}
    g_score[source] = 0
    let f_start = heuristic(maze, source, target)
    best_f[source] = f_start
    heap_push(open_set, f_start.to_long() * 2097152L + source)
    for _step in 0L..MAX_NEIGHBORS + 1L {
        if open_set.count() == 0L { break }
        let current = heap_pop(open_set) % 2097152L
        if current == target {
            var reverse_path: list<int, 1960000> = list {}
            var cur = current
            for _hop in 0L..MAX_CELLS {
                if cur < 0L { break }
                discard reverse_path.push((int)cur)
                cur = came_from[cur].to_long()
            }
            let total = reverse_path.count()
            return PathInfo { length: total, mid: mid_product(maze, reverse_path[total - 1L - total / 2L].to_long()) }
        }
        let current_g = g_score[current]
        for k in 0L..4L {
            let neighbor = maze.neighbors[current * 4L + k].to_long()
            if !is_walkable(maze.kind[neighbor]) { continue }
            let tentative_g = current_g + 1
            if tentative_g < g_score[neighbor] {
                came_from[neighbor] = (int)current
                g_score[neighbor] = tentative_g
                let f_new = tentative_g + heuristic(maze, neighbor, target)
                if f_new < best_f[neighbor] {
                    best_f[neighbor] = f_new
                    heap_push(open_set, f_new.to_long() * 2097152L + neighbor)
                }
            }
        }
    }
    none_found
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let width_value = if run { 1400L } else { 200L }
    let height = if run { 1400L } else { 30L }
    let iterations = if run { 70L } else { 2L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var rng = Rng { last: 42L }
    var maze = new_maze(width_value, height, rng)
    generate(maze)
    var result = 0L
    var last_mid = 0L
    for _round in 0L..warmup + iterations {
        let found = astar(maze, width_value + 1L, finish_cell(maze))
        result += found.length
        last_mid = found.mid
    }
    print((result + last_mid) % 4294967296L)
}
