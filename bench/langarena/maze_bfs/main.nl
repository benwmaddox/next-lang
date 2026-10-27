// LangArena Maze::BFS: breadth-first search from the start to the finish.
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

fn next_int(rng: write Rng, max: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max / 139968L
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

fn new_maze(width: long, height: long, rng: write Rng) -> Maze {
    var maze = Maze { width, height, kind: fill(WALL), neighbors: fill(0) }
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

fn bfs(maze: Maze, source: long, target: long) -> PathInfo {
    let none_found = PathInfo { length: 0L, mid: 0L }
    if source == target { return PathInfo { length: 1L, mid: mid_product(maze, source) } }
    var visited: bool[1960000] = fill(false)
    var path_cell: int[1960000] = fill(0)
    var path_parent: int[1960000] = fill(-1)
    var path_count = 1L
    var pending: queue<int, 1960000> = queue {}
    visited[source] = true
    path_cell[0L] = (int)source
    discard pending.push(0)
    for _step in 0L..MAX_CELLS + 1L {
        let path_id = (pending.pop() ?? return none_found).to_long()
        let cell = path_cell[path_id].to_long()
        for k in 0L..4L {
            let neighbor = maze.neighbors[cell * 4L + k].to_long()
            if neighbor == target {
                var reverse_path: list<int, 1960000> = list {}
                discard reverse_path.push((int)target)
                var current = path_id
                for _hop in 0L..MAX_CELLS {
                    if current < 0L { break }
                    discard reverse_path.push(path_cell[current])
                    current = path_parent[current].to_long()
                }
                let total = reverse_path.count()
                return PathInfo { length: total, mid: mid_product(maze, reverse_path[total - 1L - total / 2L].to_long()) }
            }
            if is_walkable(maze.kind[neighbor]) && !visited[neighbor] {
                visited[neighbor] = true
                path_cell[path_count] = (int)neighbor
                path_parent[path_count] = (int)path_id
                discard pending.push((int)path_count)
                path_count += 1L
            }
        }
    }
    none_found
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let width = if run { 1400L } else { 200L }
    let height = if run { 1400L } else { 30L }
    let iterations = if run { 70L } else { 2L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var rng = Rng { last: 42L }
    var maze = new_maze(width, height, rng)
    generate(maze)
    var result = 0L
    var last_mid = 0L
    for _round in 0L..warmup + iterations {
        let found = bfs(maze, width + 1L, finish_cell(maze))
        result += found.length
        last_mid = found.mid
    }
    print((result + last_mid) % 4294967296L)
}
