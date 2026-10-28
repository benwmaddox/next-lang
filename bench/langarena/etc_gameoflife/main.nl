// Etc::GameOfLife: one Cell struct per cell, each holding its 8 precomputed torus neighbour indices.
const TEST_W: long = 20L
const TEST_H: long = 20L
const TEST_ITERATIONS: long = 3L
const RUN_W: long = 500L
const RUN_H: long = 500L
const RUN_ITERATIONS: long = 500L
const NEIGHBOR_COUNT: long = 8L
const MODULUS: long = 4294967296L
const IM: long = 139968L
const IA: long = 3877L
const IC: long = 29573L
const LCG_INIT: long = 42L

struct Cell {
    alive: bool
    next_alive: bool
    neighbors: list<long, 8>
}

struct Board {
    cells: Cell[250000]
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

// The LCG step; LangArena's next_float(1.0) is last / IM.
fn next_last(last: write long) -> long {
    last = (last * IA + IC) % IM
    last
}

// Build every cell's list of 8 torus neighbour indices once, as Crystal's link_neighbors does.
fn link_neighbors(board: write Board, w: long, h: long) {
    for y: long in 0L..h {
        for x: long in 0L..w {
            let left = if x == 0L { w - 1L } else { x - 1L }
            let right = if x == w - 1L { 0L } else { x + 1L }
            let up = if y == 0L { h - 1L } else { y - 1L }
            let down = if y == h - 1L { 0L } else { y + 1L }
            var nb: list<long, 8> = list {}
            nb.push(up * w + left).unwrap()
            nb.push(up * w + x).unwrap()
            nb.push(up * w + right).unwrap()
            nb.push(y * w + left).unwrap()
            nb.push(y * w + right).unwrap()
            nb.push(down * w + left).unwrap()
            nb.push(down * w + x).unwrap()
            nb.push(down * w + right).unwrap()
            let index = y * w + x
            board.cells[index] = Cell { alive: board.cells[index].alive, next_alive: false, neighbors: nb }
        }
    }
}

fn next_generation(board: write Board, w: long, h: long) {
    for index: long in 0L..(w * h) {
        var count_value = 0L
        for k: long in 0L..NEIGHBOR_COUNT {
            let neighbor = board.cells[index].neighbors[k]
            if board.cells[neighbor].alive { count_value += 1L }
        }
        if board.cells[index].alive {
            board.cells[index].next_alive = count_value == 2L || count_value == 3L
        } else {
            board.cells[index].next_alive = count_value == 3L
        }
    }
    for index: long in 0L..(w * h) {
        board.cells[index].alive = board.cells[index].next_alive
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let w = if run { RUN_W } else { TEST_W }
    let h = if run { RUN_H } else { TEST_H }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    let prep = is_prep_mode(env)
    let rounds = if prep { warmup } else { warmup + iterations }
    var board = Board { cells: fill(Cell { alive: false, next_alive: false, neighbors: list {} }) }
    link_neighbors(board, w, h)
    var last = LCG_INIT
    // prepare: a cell lives when next_float(1.0) < 0.1, that is last / IM < 0.1, in row-major order.
    for index: long in 0L..(w * h) {
        if next_last(last) * 10L < IM { board.cells[index].alive = true }
    }
    for _round: long in 0L..rounds {
        next_generation(board, w, h)
    }
    var hash = 2166136261L
    var alive_count = 0L
    for index: long in 0L..(w * h) {
        let flag = if board.cells[index].alive { 1L } else { 0L }
        alive_count += flag
        hash = ((hash ^ flag) * 16777619L) % MODULUS
    }
    print((hash + alive_count) % MODULUS)
}
