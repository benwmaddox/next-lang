// LangArena Compress::HuffEncode: Huffman coding. The tree lives in a list of nodes
// and refers to children by index; a sorted queue of node indices builds it.
type Octet = int 0..=255
type Slot = long 0..=512

struct Node {
    frequency: long
    byte_value: long
    is_leaf: bool
    left: long
    right: long
}

struct Tree {
    nodes: list<Node, 512>
    root: long
}

struct Codes {
    lengths: long[256]
    values: long[256]
}

struct Encoded {
    data: Bytes max 1000002
    bit_count: long
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

fn generate_test_data(size: long) -> list<byte, 1000002> {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: list<byte, 1000002> = list {}
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

// Insert a node index into the queue (from `head` on) after every node of equal or lower frequency.
fn insert_sorted(queue: write list<long, 512>, head: long, nodes: list<Node, 512>, id: long) {
    var position: long = queue.count()
    let frequency = nodes[id].frequency
    for at: long in head..queue.count() {
        if nodes[queue[at]].frequency > frequency {
            position = at
            break
        }
    }
    discard queue.insert((Slot)(position), id)
}

fn build_huffman_tree(frequencies: long[256]) -> Tree {
    var tree = Tree { nodes: list {}, root: -1L }
    var queue: list<long, 512> = list {}
    for byte_value: long in 0L..256L {
        if frequencies[byte_value] > 0L {
            discard tree.nodes.push(Node {
                frequency: frequencies[byte_value],
                byte_value: byte_value,
                is_leaf: true,
                left: -1L,
                right: -1L
            })
            insert_sorted(queue, 0L, tree.nodes, tree.nodes.count() - 1L)
        }
    }
    if queue.count() == 0L {
        return tree
    }
    if queue.count() == 1L {
        let only = queue[0L]
        discard tree.nodes.push(Node { frequency: 0L, byte_value: 0L, is_leaf: true, left: -1L, right: -1L })
        discard tree.nodes.push(Node {
            frequency: tree.nodes[only].frequency,
            byte_value: 0L,
            is_leaf: false,
            left: only,
            right: tree.nodes.count() - 1L
        })
        tree.root = tree.nodes.count() - 1L
        return tree
    }
    var head = 0L
    for _step: long in 0L..512L {
        if queue.count() - head <= 1L { break }
        let left = queue[head]
        let right = queue[head + 1L]
        head += 2L
        discard tree.nodes.push(Node {
            frequency: tree.nodes[left].frequency + tree.nodes[right].frequency,
            byte_value: 0L,
            is_leaf: false,
            left: left,
            right: right
        })
        insert_sorted(queue, head, tree.nodes, tree.nodes.count() - 1L)
    }
    tree.root = queue[queue.count() - 1L]
    tree
}

recursive fn build_huffman_codes(nodes: list<Node, 512>, id: long, code: long, length: long, codes: write Codes) {
    let node = nodes[id]
    if node.is_leaf {
        if length > 0L || node.byte_value != 0L {
            codes.lengths[node.byte_value] = length
            codes.values[node.byte_value] = code
        }
    } else {
        if node.left >= 0L {
            build_huffman_codes(nodes, node.left, code * 2L, length + 1L, codes)
        }
        if node.right >= 0L {
            build_huffman_codes(nodes, node.right, code * 2L + 1L, length + 1L, codes)
        }
    }
}

fn huffman_encode(data: list<byte, 1000002>, codes: Codes) -> Encoded {
    var encoded = Encoded { data: Bytes.empty(), bit_count: 0L }
    var current = 0L
    var bit_pos = 0L
    for i: long in 0L..data.count() {
        let index = data[i].to_long()
        let code = codes.values[index]
        let length = codes.lengths[index]
        for j: long in 0L..length {
            let shift = length - 1L - j
            if ((code >> shift) & 1L) != 0L {
                current = current | (1L << (7L - bit_pos))
            }
            bit_pos += 1L
            encoded.bit_count += 1L
            if bit_pos == 8L {
                discard encoded.data.push((Octet)((int)current))
                current = 0L
                bit_pos = 0L
            }
        }
    }
    if bit_pos > 0L {
        discard encoded.data.push((Octet)((int)current))
    }
    encoded
}

fn encode_once(data: list<byte, 1000002>) -> Encoded {
    var frequencies: long[256] = fill(0L)
    for i: long in 0L..data.count() {
        frequencies[data[i].to_long()] += 1L
    }
    let tree = build_huffman_tree(frequencies)
    var codes = Codes { lengths: fill(0L), values: fill(0L) }
    if tree.root >= 0L {
        build_huffman_codes(tree.nodes, tree.root, 0L, 0L, codes)
    }
    huffman_encode(data, codes)
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let prep = is_prep_mode(env)
    let size = if run_mode { 1000002L } else { 52L }
    let iterations = if run_mode { 200L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    let test_data = generate_test_data(size)
    var result = 0L
    let rounds = if prep { warmup } else { warmup + iterations }
    for _w: long in 0L..rounds {
        let encoded = encode_once(test_data)
        result = (result + encoded.data.count()) % 4294967296L
    }
    print(result)
}
