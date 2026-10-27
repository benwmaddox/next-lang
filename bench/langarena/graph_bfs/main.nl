// LangArena Graph::BFS: shortest path from vertex 0 to the last vertex by breadth-first search.
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

fn bfs_shortest_path(start: int[500001], adj: int[11000000], vertices: long, source: long, target: long) -> long {
    if source == target { return 0L }
    var visited: bool[500000] = fill(false)
    var dist: int[500000] = fill(0)
    var queue_v: queue<int, 500000> = queue {}
    visited[source] = true
    discard queue_v.push((int)source)
    for _step in 0L..vertices {
        let v = queue_v.pop() ?? return -1L
        let vl = v.to_long()
        let d = dist[vl]
        for e in start[vl].to_long()..start[vl + 1L].to_long() {
            let neighbor = adj[e].to_long()
            if neighbor == target { return (d + 1).to_long() }
            if !visited[neighbor] {
                visited[neighbor] = true
                dist[neighbor] = d + 1
                discard queue_v.push((int)neighbor)
            }
        }
    }
    -1L
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let vertices = if run { 500000L } else { 100L }
    let jumps = if run { 20L } else { 3L }
    let jump_len = if run { 1000L } else { 100L }
    let iterations = if run { 40L } else { 3L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

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
    for _round in 0L..warmup + iterations {
        let length = bfs_shortest_path(start, adj, vertices, 0L, vertices - 1L)
        result = (result + length + 4294967296L) % 4294967296L
    }
    print(result)
}
