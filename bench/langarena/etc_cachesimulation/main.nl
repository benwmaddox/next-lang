// Etc::CacheSimulation: an LRU cache (map + doubly linked list in a node array) driven by LangArena's LCG.
const TEST_VALUES: long = 2000L
const TEST_SIZE: long = 1000L
const TEST_ITERATIONS: long = 2L
const RUN_VALUES: long = 5000L
const RUN_SIZE: long = 2500L
const RUN_ITERATIONS: long = 5000L
const MODULUS: long = 4294967296L
const IM: long = 139968L
const IA: long = 3877L
const IC: long = 29573L
const LCG_INIT: long = 42L

struct Node {
    key: Ascii max 16
    value: Ascii max 24
    prev: int
    next: int
}

struct Cache {
    capacity: long
    index: map<Ascii max 16, int, 8192>
    nodes: list<Node, 2500>
    free: list<int, 2500>
    head: int
    tail: int
    size: long
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn new_cache(capacity: long) -> Cache {
    Cache { capacity: capacity, index: map {}, nodes: list {}, free: list {}, head: -1, tail: -1, size: 0L }
}

// LangArena's next_int(max_value): the LCG step, then floor(last / IM * max_value).
fn next_int(last: write long, max_value: long) -> long {
    last = (last * IA + IC) % IM
    last * max_value / IM
}

fn move_to_front(cache: write Cache, node: int) {
    if node == cache.head { return }
    let prev = cache.nodes[node.to_long()].prev
    let next = cache.nodes[node.to_long()].next
    if prev >= 0 { cache.nodes[prev.to_long()].next = next }
    if next >= 0 { cache.nodes[next.to_long()].prev = prev }
    if node == cache.tail { cache.tail = prev }
    cache.nodes[node.to_long()].prev = -1
    cache.nodes[node.to_long()].next = cache.head
    if cache.head >= 0 { cache.nodes[cache.head.to_long()].prev = node }
    cache.head = node
    if cache.tail < 0 { cache.tail = node }
}

fn add_to_front(cache: write Cache, node: int) {
    cache.nodes[node.to_long()].next = cache.head
    if cache.head >= 0 { cache.nodes[cache.head.to_long()].prev = node }
    cache.head = node
    if cache.tail < 0 { cache.tail = node }
}

fn remove_oldest(cache: write Cache) {
    if cache.tail >= 0 {
        let tail_node = cache.tail
        let key = cache.nodes[tail_node.to_long()].key
        cache.index.remove(key)
        let prev = cache.nodes[tail_node.to_long()].prev
        if prev >= 0 { cache.nodes[prev.to_long()].next = -1 }
        cache.tail = prev
        if tail_node == cache.head { cache.head = -1 }
        cache.free.push(tail_node).unwrap()
        cache.size -= 1L
    }
}

// True (and the entry becomes most recent) when the key is cached.
fn get(cache: write Cache, key: Ascii max 16) -> bool {
    match cache.index.get(key) {
        some(node) => {
            move_to_front(cache, node)
            true
        },
        none => false
    }
}

fn put(cache: write Cache, key: Ascii max 16, value: Ascii max 24) {
    match cache.index.get(key) {
        some(node) => {
            let old = cache.nodes[node.to_long()]
            cache.nodes[node.to_long()] = Node { key: old.key, value: value, prev: old.prev, next: old.next }
            move_to_front(cache, node)
        },
        none => {
            if cache.size >= cache.capacity { remove_oldest(cache) }
            let fresh = Node { key: key, value: value, prev: -1, next: -1 }
            var slot = 0
            match cache.free.pop() {
                some(reused) => {
                    slot = reused
                    cache.nodes[slot.to_long()] = fresh
                },
                none => {
                    slot = (int)cache.nodes.count()
                    cache.nodes.push(fresh).unwrap()
                }
            }
            cache.index.set(key, slot).unwrap()
            add_to_front(cache, slot)
            cache.size += 1L
        }
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let values = if run { RUN_VALUES } else { TEST_VALUES }
    let size = if run { RUN_SIZE } else { TEST_SIZE }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var cache = new_cache(size)
    var hits = 0L
    var misses = 0L
    var last = LCG_INIT
    // The warmup runs keep their cache and counters; only the random generator restarts.
    for round: long in 0L..(warmup + iterations) {
        if round == warmup { last = LCG_INIT }
        let iteration_id = (int)(if round < warmup { round } else { round - warmup })
        for _step: long in 0L..1000L {
            let key: Ascii max 16 = "item_" + str((int)next_int(last, values))
            if get(cache, key) {
                hits += 1L
                put(cache, key, "updated_" + str(iteration_id))
            } else {
                misses += 1L
                put(cache, key, "new_" + str(iteration_id))
            }
        }
    }
    var result = 5432L
    result = (result * 32L + hits) % MODULUS
    result = (result * 32L + misses) % MODULUS
    result = (result * 32L + cache.size) % MODULUS
    print(result)
}
