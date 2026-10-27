// LangArena Maze::Generator: dig a maze with a randomised depth-first walk, repeatedly.
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
// ---- end of shared maze code ----

fn reset(maze: write Maze) {
    for cell in 0L..maze.width * maze.height {
        if maze.kind[cell] == SPACE { maze.kind[cell] = WALL }
    }
    maze.kind[maze.width + 1L] = START
    maze.kind[finish_cell(maze)] = FINISH
}

fn maze_checksum(maze: Maze) -> long {
    var hasher = 2166136261L
    for y in 0L..maze.height {
        for x in 0L..maze.width {
            if maze.kind[y * maze.width + x] == SPACE {
                hasher = ((hasher ^ (x * y)) * 16777619L) % 4294967296L
            }
        }
    }
    hasher
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let width_value = if run { 1400L } else { 200L }
    let height = if run { 1400L } else { 30L }
    let iterations = if run { 10L } else { 2L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var rng = Rng { last: 42L }
    var maze = new_maze(width_value, height, rng)
    var result = 0L
    for _round in 0L..warmup + iterations {
        reset(maze)
        generate(maze)
        result += maze.kind[(height / 2L) * width_value + width_value / 2L].to_long()
    }
    print((result + maze_checksum(maze)) % 4294967296L)
}
