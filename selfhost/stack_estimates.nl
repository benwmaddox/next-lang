// The data stack an entry point (main, or a function a job starts with spawn) can need, worked out when the program is built, so the
// runtime reserves that much address space for the job instead of a fixed 64 MiB (or 32 GiB for main).
//
// A function's own use is the sum of all its blocks' ranges (regions.nl, over-counted: blocks that follow each other are added). The
// entry's bound is its own use plus the deepest of the functions it calls, down the call graph. A function that is reached by a cycle
// (recursion), through a function value (indirect call), or that is not a user function the build planned, makes the bound unknown, and
// an unknown bound keeps the runtime's generic default. The calculation is trusted as it stands, with no safety factor added on top: it
// is checked instead (the whole test suite runs with the exact bound reserved, and tests/py/test_stack_estimates.py compares what a job
// used with what it reserved), and a job that did exceed it would stop with a data stack overflow naming the entry point. What is added
// is only rounding: the reservation is rounded up to a power of two, at least 64 KiB, so that jobs with nearby bounds reserve the same
// size and share pooled stacks (a stack is reused only by a job whose reservation fits it) and the sizes stay few and readable.

const STACK_BOUND_FLOOR_BYTES: long = 65536L
const STACK_BOUND_CALL_DEPTH: long = 40L
const STACK_BOUND_SCAN_BUDGET: long = 3000000L

recursive fn stack_worst_case(
    tables: ParseTables,
    compiler: CompilerTables,
    function_id: long,
    depth: long,
    path: write list<long, 48>,
    budget: write long,
) -> long {
    if function_id < 0L || function_id >= compiler.functions.count() || depth > STACK_BOUND_CALL_DEPTH { return -1L }
    for earlier in path {
        if earlier == function_id { return -1L }
    }
    if function_id >= compiler.function_frames.count() { return -1L }
    let frame = compiler.function_frames[function_id]
    if frame < 0L { return -1L }
    let body = compiler.functions[function_id].body
    if body < 0L || body >= tables.nodes.count() { return -1L }
    let first = body - tables.nodes[body].subtree + 1L
    budget -= body - first + 1L
    if budget < 0L { return -1L }
    match path.push(function_id) { ok(_) => (), err(_) => return -1L }
    // jobs a spawn starts run on stacks of their own: their calls are not this function's
    var job_calls: list<long, 64> = list {}
    for node in first..body + 1L {
        if tables.nodes[node].kind == NodeKind.Spawn && compiler.facts[node].literal == 1L {
            match job_calls.push(job_call_node(tables, compiler, node)) { ok(_) => (), err(_) => { stack_path_pop(path); return -1L } }
        }
    }
    var deepest = 0L
    for node in first..body + 1L {
        let kind = tables.nodes[node].kind
        if kind == NodeKind.IndirectCall {
            stack_path_pop(path)
            return -1L
        }
        if (kind == NodeKind.Call || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall) && compiler.facts[node].function >= 0L {
            var is_job_call = false
            for job_call in job_calls { if job_call == node { is_job_call = true } }
            if is_job_call { continue }
            let below = stack_worst_case(tables, compiler, compiler.facts[node].function, depth + 1L, path, budget)
            if below < 0L {
                stack_path_pop(path)
                return -1L
            }
            if below > deepest { deepest = below }
        }
    }
    stack_path_pop(path)
    frame + 256L + deepest
}

fn stack_path_pop(path: write list<long, 48>) {
    match path.pop() {
        some(_) => (),
        none => (),
    }
}

// What to give the runtime as the entry point's reservation: the bound with its margin, or 4096 (no estimate: the runtime's default).
fn stack_reservation_estimate(tables: ParseTables, compiler: CompilerTables, function_id: long) -> long {
    if !compiler.c_runtime || compiler.core_mode { return 4096L }
    var path: list<long, 48> = list {}
    var budget = STACK_BOUND_SCAN_BUDGET
    let bound = stack_worst_case(tables, compiler, function_id, 0L, path, budget)
    if bound < 0L || bound > 4611686018427387904L / 4L { return 4096L }
    var size = STACK_BOUND_FLOOR_BYTES
    for step in 0L..62L {
        if size >= bound { break }
        size = size * 2L
    }
    size
}
