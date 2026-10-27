// Etc::GameOfLife: Conway's life on a torus, seeded from LangArena's LCG, hashed with FNV-1a.
const TEST_W: long = 20L
const TEST_H: long = 20L
const TEST_ITERATIONS: long = 3L
const RUN_W: long = 500L
const RUN_H: long = 500L
const RUN_ITERATIONS: long = 500L
const MODULUS: long = 4294967296L
const IM: long = 139968L
const IA: long = 3877L
const IC: long = 29573L
const LCG_INIT: long = 42L

struct Board {
    alive: bool[250000]
    next: bool[250000]
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

// The LCG step; LangArena's next_float(1.0) is last / IM.
fn next_last(last: write long) -> long {
    last = (last * IA + IC) % IM
    last
}

fn neighbors(board: Board, x: long, y: long, w: long, h: long) -> long {
    let left = if x == 0L { w - 1L } else { x - 1L }
    let right = if x == w - 1L { 0L } else { x + 1L }
    let up = if y == 0L { h - 1L } else { y - 1L }
    let down = if y == h - 1L { 0L } else { y + 1L }
    var count = 0L
    if board.alive[up * w + left] { count += 1L }
    if board.alive[up * w + x] { count += 1L }
    if board.alive[up * w + right] { count += 1L }
    if board.alive[y * w + left] { count += 1L }
    if board.alive[y * w + right] { count += 1L }
    if board.alive[down * w + left] { count += 1L }
    if board.alive[down * w + x] { count += 1L }
    if board.alive[down * w + right] { count += 1L }
    count
}

fn next_generation(board: write Board, w: long, h: long) {
    for y: long in 0L..h {
        for x: long in 0L..w {
            let count = neighbors(board, x, y, w, h)
            let index = y * w + x
            if board.alive[index] {
                board.next[index] = count == 2L || count == 3L
            } else {
                board.next[index] = count == 3L
            }
        }
    }
    for index: long in 0L..(w * h) {
        board.alive[index] = board.next[index]
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let w = if run { RUN_W } else { TEST_W }
    let h = if run { RUN_H } else { TEST_H }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var board = Board { alive: fill(false), next: fill(false) }
    var last = LCG_INIT
    // prepare: a cell lives when next_float(1.0) < 0.1, that is last / IM < 0.1.
    for index: long in 0L..(w * h) {
        if next_last(last) * 10L < IM { board.alive[index] = true }
    }
    for _round: long in 0L..(warmup + iterations) {
        next_generation(board, w, h)
    }
    var hash = 2166136261L
    var alive_count = 0L
    for index: long in 0L..(w * h) {
        let flag = if board.alive[index] { 1L } else { 0L }
        alive_count += flag
        hash = ((hash ^ flag) * 16777619L) % MODULUS
    }
    print((hash + alive_count) % MODULUS)
}
