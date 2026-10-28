// LangArena Graph::AStar: shortest path from vertex 0 to the last vertex by A* with the heuristic (target - v).
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

// Min-heap of (f, vertex) pairs packed as f * 2^20 + vertex, ordered like the reference's Node.
fn heap_push(heap: write list<long, 11000000>, key: long) {
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

fn heap_pop(heap: write list<long, 11000000>) -> long {
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

fn a_star_shortest_path(start: int[500001], adj: int[11000000], source: long, target: long) -> long {
    if source == target { return 0L }
    var g_score: int[500000] = fill(2147483647)
    var best_f: int[500000] = fill(2147483647)
    var open_set: list<long, 11000000> = list {}
    g_score[source] = 0
    let f_start = (int)(target - source)
    best_f[source] = f_start
    heap_push(open_set, f_start.to_long() * 1048576L + source)
    for _step in 0L..MAX_ENTRIES + 1L {
        if open_set.count() == 0L { break }
        let key = heap_pop(open_set)
        let current = key % 1048576L
        if current == target { return g_score[current].to_long() }
        let tentative_g = g_score[current] + 1
        for e in start[current].to_long()..start[current + 1L].to_long() {
            let neighbor = adj[e].to_long()
            if tentative_g < g_score[neighbor] {
                g_score[neighbor] = tentative_g
                let f_new = tentative_g + (int)(target - neighbor)
                if f_new < best_f[neighbor] {
                    best_f[neighbor] = f_new
                    heap_push(open_set, f_new.to_long() * 1048576L + neighbor)
                }
            }
        }
    }
    -1L
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
    let iterations = if run { 1000L } else { 3L }
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
        let length = a_star_shortest_path(start, adj, 0L, vertices - 1L)
        result = (result + length + 4294967296L) % 4294967296L
    }
    print(result)
}
