// LangArena Graph::DFS: path length from vertex 0 to the last vertex by depth-first search with pruning.
// The graph is stored compressed (CSR): start[v]..start[v + 1] indexes v's neighbours in adj, in
// the same order the reference's per-vertex vectors get them. It's built in two passes over the
// same random sequence: the first counts degrees, the second fills.
const MAX_VERTICES: long = 500000L
const MAX_ENTRIES: long = 11000000L   // 2 x edges; the run parameters give 5,283,341 edges

struct Rng { last: long }

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

fn add_edge(count_only: bool, u: long, v: long, start: write int[500001], pos: write int[500000], adj: write int[11000000]) {
    if count_only {
        start[u + 1L] += 1
        start[v + 1L] += 1
    } else {
        adj[pos[u].to_long()] = (int)v
        pos[u] += 1
        adj[pos[v].to_long()] = (int)u
        pos[v] += 1
    }
}

fn generate(count_only: bool, vertices: long, jumps: long, jump_len: long, start: write int[500001], pos: write int[500000], adj: write int[11000000]) {
    var rng = Rng { last: 42L }
    for i in 1L..vertices {
        add_edge(count_only, i, i - 1L, start, pos, adj)
    }
    for v in 0L..vertices {
        let num_jumps = next_int(rng, jumps)
        for _j in 0L..num_jumps {
            let offset = next_int(rng, jump_len) - jump_len / 2L
            let u = v + offset
            if u >= 0L && u < vertices && u != v {
                add_edge(count_only, v, u, start, pos, adj)
            }
        }
    }
}

struct Frame { v: int, dist: int }

fn dfs_find_path(start: int[500001], adj: int[11000000], source: long, target: long) -> long {
    if source == target { return 0L }
    var visited: bool[500000] = fill(false)
    var stack: list<Frame, 11000000> = list {}
    discard stack.push(Frame { v: (int)source, dist: 0 })
    var best_path = 2147483647
    for _step in 0L..MAX_ENTRIES + 1L {
        let frame = stack.pop() ?? break
        let vl = frame.v.to_long()
        if visited[vl] || frame.dist >= best_path { continue }
        visited[vl] = true
        for e in start[vl].to_long()..start[vl + 1L].to_long() {
            let neighbor = adj[e].to_long()
            if neighbor == target {
                best_path = min(best_path, frame.dist + 1)
                continue
            }
            if !visited[neighbor] {
                discard stack.push(Frame { v: (int)neighbor, dist: frame.dist + 1 })
            }
        }
    }
    if best_path == 2147483647 { -1L } else { best_path.to_long() }
}

fn is_prep_mode(env: Env) -> bool {
    match env.args().get(1L) {
        some(_argument) => true,
        none => false
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let vertices = if run { 500000L } else { 100L }
    let jumps = if run { 20L } else { 3L }
    let jump_len = if run { 1000L } else { 100L }
    let iterations = if run { 15L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    let prep = is_prep_mode(env)
    let rounds = if prep { warmup } else { warmup + iterations }

    var start: int[500001] = fill(0)
    var pos: int[500000] = fill(0)
    var adj: int[11000000] = fill(0)
    generate(true, vertices, jumps, jump_len, start, pos, adj)
    for v in 0L..vertices {
        start[v + 1L] += start[v]
        pos[v] = start[v]
    }
    generate(false, vertices, jumps, jump_len, start, pos, adj)

    var result = 0L
    for _round in 0L..rounds {
        let length = dfs_find_path(start, adj, 0L, vertices - 1L)
        result = (result + length + 4294967296L) % 4294967296L
    }
    print(result)
}
