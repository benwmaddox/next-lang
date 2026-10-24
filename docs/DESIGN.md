# A general-purpose language: correct, easy, efficient

Oct 23, 2026 · Ben Maddox. Working copy, refined with Codex; reviews and replies are in [reviews/](reviews/). The two diagrams are in the original shared doc: https://claude.ai/artifact/AfD3gnVW8QqwrVXomjv48H

## Goals and non-goals

One language that is hard to get wrong, quick to work in, and within about 10% of C on CPU and memory, for servers, games and tools (weighted equally). Each goal has a test, not an adjective:

- **Correct:** the compiler enforces a stated set of properties (no null, no data races, no dangling ids, exhaustive matches, refinements, effects), and the language's own tests catch most of the rest. Measured by seeded slips caught at build time, scenarios passing, and fast-versus-reference checks. No language catches every wrong program; this one aims to catch the common ones before production.
- **Easy:** a small edit is running again within 3 s, a release builds in under 30 s, and every error names the fix. Measured by edit-to-running time and the mutation harness's "did you mean" rate.
- **Efficient:** no garbage collector, no allocation in steady state, compute at 0.9x of C or better, servers within 1.2x of the optimized Rust port's memory. Measured on DEFLATE, a Campfire-class server, a game simulation and a parallel tool (see Validation).

Non-goals for the first version:

- Full dependent types or proofs of arbitrary properties (refinements stay decidable, see Types).
- Pointer graphs with arbitrary aliasing; long-lived links are typed ids.
- 32-bit and WebAssembly targets: v1 is 64-bit only (Windows, Linux, macOS, 64-bit Android), because the stack design relies on large address reservations. WebAssembly comes later with its own stack design (decided 2026-10-24).
- Replacing Burin or the other languages: Burin continues as its own web language, and this is a separate project in its own folder that borrows their ideas and code.
- A package ecosystem or governance model before the core proves itself.

## Evidence from the six languages

The design keeps what was measured to work in four weeks of building six languages, and drops what was measured not to.

| Idea | From | Evidence | Verdict |
| --- | --- | --- | --- |
| Scenarios, golden outputs, fast-versus-reference checks | crudspec, AgentLang, Burin | Scenarios caught 86% of seeded bugs; the checker's main rule alone, 9% (crudspec H1) | Keep, as language features |
| Work done before run time | Burin, AgentLang | Constant tables: CRC-32 on 64 B 683 to 75 ns (against a C version that also builds its table per call); write-time pieces: Campfire 54k to 69k pages/s | Keep |
| Facts handed to LLVM, not a home-made optimizer | Burin helpers | DEFLATE 0.70x to 0.85x of clang -O2 in Burin's measured table (dickens, one core, median of 9), 0.89x after later sign-analysis work | Keep |
| Load only what is used | Burin | Guarded list loads: +27% to +50% pages/s | Keep, generalized |
| Explicit bounded state, deterministic ticks | Stasis, Burin | Replays and live swap for free; bounded lists | Keep |
| Rules declared once, carried to every layer | crudspec | `max 80` = CHECK, maxlength, schema limit; 0.26x Rails' lines | Keep, generalized |
| Inferred effects and capabilities | Hobthrush | Shortest call path when a bound is exceeded | Keep |
| Bump memory freed in bulk | Burin, AgentLang, Goose | Zero allocations on the fast path | Keep |
| Vocabulary rules as the reliability lever | AgentLang | F# equally correct, 1.7 to 5x fewer agent exchanges | Drop |
| Interpreter as the shipped runtime | AgentLang, crudspec v1 | Both replaced by compiled code | Drop |
| A platform garbage collector | Hobthrush (.NET) | No control over memory or speed | Drop |
| Two implementation stacks | crudspec (TypeScript + Go) | Double the upkeep | Drop |
| Caches cleared on every write | crudspec | 17k to 0.6k pages/s at 50 posts/s | Drop |

## Memory: data lives in tables, computing lives on stacks

There are two lifetimes and no garbage collector: long-lived data in declared tables, everything temporary on scope stacks freed in one store.

**Tables** hold what outlives a call (a game's world, a server's records, a tool's index).

- A table is rows of one record type, stored as one array per field (structure of arrays, as Stasis lowers it).
- **Fixed-size fields** (numbers, ids, enums, small records) sit in their column directly.
- **Variable-size fields** (text, bytes, a list inside a row) can't sit in a fixed-width column. The column holds `{offset, length}` into the table's own payload blocks: large append-only byte blocks that the table owns. Changing a text field writes the new bytes at the end of the current payload block and updates the row's `{offset, length}`; the old bytes become garbage inside the block. When more than half of a block is garbage, the writer compacts it: it copies the live bytes to a fresh block and rewrites the rows' `{offset, length}` in a new version, while the old block stays alive for older versions still pinned. Finding the rows that point into a block means scanning its rows' columns, so compaction runs in the writer's idle time with a budget per batch, not inside a client's write. Payload blocks are shared between versions like row blocks (see Tables across threads).
- **Typed ids:** rows refer to each other by `Item.Id`, 64 bits: a 32-bit slot and a 32-bit generation counter. The table it belongs to is part of the type, not stored in the id. In v1 each declared, published table set exists once per program, so the type alone names the table; several published instances of one table set (one per tenant, say) would need an instance field and are left for later. Two other kinds of table have scoped ids: frozen tables (see Frozen tables), and **job-owned tables**, private tables a job creates for its own use (a checker's type cache, a game's scratch grid). A job-owned table is created from a scope token (`let cache = table TypeEntry in job`), its ids are typed by that token (`cache.TypeEntry.Id`), and they can't leave the job or mix with another job's. The table is freed with the job. Deleting a row bumps its slot's generation, so an old id no longer matches. Looking up an id returns `Option`: `none` for a stale id, never a dangling pointer. A slot whose generation reaches its maximum is retired, never reused, so wraparound can't make a stale id match again.
- A table is in memory or backed by SQLite with the same syntax; queries on a SQLite table compile to SQL.
- Invariants are declared on tables and checked on every write (see Correctness).
- One writer per table set changes it. Readers on other threads read an immutable snapshot, pinned once per job, never per row (Burin's model; details in Tables across threads).

**Stacks** hold temporaries.

- Each job (a request, a tick, a task) runs on N data stacks, each a large reserved address range with a bump pointer. N is computed by the compiler.
- At most one growing value per stack, always on top of it (Goose's rule). The compiler picks each growing value's stack (see How the compiler assigns stacks). So growth is a pointer moving up, nothing moves, and positions stay valid.
- Fixed-size values sit in registers or the native stack; small arrays too (up to 4 KB, as Burin's helpers do).
- A scope's memory is freed by setting its stacks back: one store each. Kept pages stay mapped for the next job (time over memory).
- **Growth is bounded by design** (see Loops can't quietly fill a stack): every value a loop keeps growing has a maximum the compiler knows, so most entry points have a worst-case stack size computed at build time.
- **Growing past a stack's reservation fails the job** (decided 2026-10-24), which bounded growth makes rare: the request, tick or task ends with an error and goes through the job-failure steps (see Types, Failures). The program keeps running. Code doesn't handle a `Result` on every push; the check is one predictable compare.

**References** exist only as parameters: a function may read, write or grow what it is handed, but cannot store or return a reference. So no lifetime annotations are needed, and Goose's "roots" check reduces to a call-graph rule.

**No overlapping arguments:** a call may not pass two arguments whose memory could overlap when either is written or grown. The check works on what each argument is part of (its owner: a local, a parameter, a row) and the fields or index ranges it covers, not on how the expressions look: passing a record for reading and one of its own fields for writing is refused, while two different fields of one record, or `a[0..n]` and `a[n..m]`, are allowed because they're provably apart. Where the compiler can't prove two arguments apart it refuses the call and says so. That proof, and only that proof, is what lets it give LLVM `noalias` (a promise that two pointers never refer to the same memory).

Between the two: a value moves from a stack into a table by copy (`create Item { … }`), and from a table onto a stack by reading fields. Reading a large field needn't copy: a function can take a read-only view of it (see Frozen tables).

*(Diagram in the shared Claude Doc: memory model · tables, snapshot, per-thread stacks.)*

The writer changes tables and publishes snapshots that readers share; every job computes on its own stacks, freed in bulk.

## Threads and data stacks

A fixed set of threads, one per core. Each job owns N data stacks that only it touches while it runs. So the common operations (push, free a scope, read a table) take no locks and no atomic operations (the special CPU instructions threads use to update shared memory safely, each costing far more than an ordinary store), and nothing mutable is shared.

### Thread kinds and jobs

- **Workers,** one per core, pinned. Each runs jobs: requests, tasks or game ticks.
- **Jobs can wait** (decided 2026-10-24). A job that waits for I/O (a call to another service, a slow file, a timer) is suspended and the worker runs other jobs meanwhile; when the I/O completes, the job resumes on the same worker where it stopped. Code reads straight-line, with no `async` in source (Go's goroutines work this way). A suspended job keeps its own native stack and its own N data stacks; that's what makes resuming possible.
  - Only some calls can suspend, and the compiler knows which: every function has a *may suspend* property, inferred across calls like an effect. The calls that suspend directly are I/O (`net`, `fs`), `clock` sleeps, `spawn` joins, a parallel loop's join, and sending a change to the writer (`db.write`, which waits for its reply). Before a call that may suspend, a function writes its cached stack tops back to memory, as it does before any call that can reach those stacks.
  - Each worker keeps a pool of free stack sets, so starting a job takes one from the pool, not a system call. The pool is sized by load, and a set's touched pages stay mapped when it goes back (time over memory).
  - A job doesn't move between workers in v1. That keeps every stack single-threaded, with no locks.
  - **A snapshot pin never spans a wait,** with one exception below. Before a call that can suspend, the job's views of the snapshot must have ended (the compiler refuses a view live across such a call) and the runtime releases its pin. After the wait the job pins the then-current snapshot, so what follows is a new read phase that may see newer data. A waiting job therefore never holds old table versions alive, and can't stall the writer.
  - **The exception, a parallel loop's join:** the chunks read the snapshot the caller had pinned, so the caller's pin is held, structured, until every chunk has stopped. Chunks use that root, never a newer one, and don't pin on their own. That retention counts against the slow-reader budget like any pin, and it's bounded by the loop's time limit.
  - **Time limits are enforced on waiting jobs too:** a job past its deadline is cancelled by the runtime, whether running or suspended (its pending I/O is cancelled), and goes through the job-failure steps. A running job notices at its next cancellation poll: loops that keep a step budget check it there, and loops that provably end (and so drop the budget) still poll a cancellation flag in the job's context every few thousand iterations, one load and compare. A foreign call that doesn't return can delay this; the deadline is enforced when it does.
  - **Admission:** a worker starts a new job only while committed memory and reserved address space stay under the configured limits; past them, a request gets a "busy, retry" response (HTTP 503 with `Retry-After` for servers) and other jobs wait in a bounded queue.
- **The writer,** one per table set. It applies change batches in order and publishes snapshots (Burin's model). Workers send it change requests on a queue and wait (suspended) for the reply.
- **Transactions** (decided 2026-10-24): each change request is one batch, applied all or nothing. Changes that must succeed together go in one `transaction { … }`, which is sent as a single batch. Once the writer has committed a batch it stays committed: a job that fails later doesn't undo it, just as an email it sent can't be unsent.
- **A transaction decides on the writer** (proposed 2026-10-24, Ben to confirm). If two jobs read the same snapshot showing one item in stock and each sends "set stock to zero, record a sale", both sales succeed. So a transaction's body, its checks as well as its writes, runs on the writer against the writer's latest version, as Burin's actions do. Inside it, reads see that latest version, not the job's snapshot. A transaction body can't suspend (no I/O, no waits) and has a step budget, so it can't stall the writer. Values the job computed earlier go in as arguments. The alternative, version-checked writes that reject a decision made on stale data and make the job retry, is left for later if writer time becomes the bottleneck.
- **Reads, three kinds:** ordinary table reads see the job's pinned snapshot; reads inside a transaction see the writer's latest version; `db.read` reads a SQLite table's latest committed state directly, for the rare query a snapshot doesn't cover.
- **Batch states:** queued, applying, then committed or aborted. If the sending job fails while its batch is queued, the batch is cancelled; if it's being applied, the writer finishes or aborts it and acknowledges before the job's cleanup frees the buffers the batch was sent from.
- **Parallel loops** borrow the workers (fork and join) rather than starting threads.
- The thread count is fixed at start (configured; the number of cores by default).

### N stacks per job

- N is computed at build time per entry point (a request handler, a job, a tick, a parallel loop's body): the highest stack index any call chain from it can use, counting each function's window, the destinations of returned values and the fixed-scratch stack. Counting only how many growing values are live at once isn't enough, since windows are consecutive and can leave gaps.
- Each stack is a reserved address range with a guard page (an unmapped page that traps if touched) at its end. Pages are committed on first touch and kept between jobs (time over memory). They're given back only when a stack's high-water mark stays far above its use, or on request.
- **Reservations are sized per entry point, per stack.** Because growth is bounded (Loops can't quietly fill a stack), the compiler computes each stack's worst case for an entry point and reserves that, rounded up to a page. Only an entry point with an unbounded source left (see that section) gets the default reservation, 64 MB per stack, configurable.
- **Address space and memory, worked out:** a process can address 128 TiB on 64-bit Windows and Linux. A request handler whose stacks are bounded at 1 MB each, with N = 8, reserves 8 MB per job: 100,000 waiting jobs reserve 0.8 TB. With the 64 MB default instead, 100,000 jobs would reserve 51 TB, so admission control (Thread kinds and jobs) caps how many jobs with default reservations may exist at once. Committed memory is separate: a waiting job that touched one 4 KiB page on each of 8 stacks holds 32 KiB plus its native stack, so 10,000 such jobs hold over 312 MiB before their native stacks. These are estimates; the server validation measures them.

### How the compiler assigns stacks

The compiler gives every function a **stack contract**, computed from its body and its callees, the way a type is:

- **Window:** how many consecutive stacks the function needs for its own growing locals and its callees', `k`. A caller passes the index of the first free stack, the *base*; the callee's own scratch uses stacks base to base + k − 1.
- **Inputs:** each reference parameter's mode, read, write or grow. A growing parameter is a value at the top of one of the caller's stacks, below base; the callee grows it in place. That named stack is the one exception to "nothing below base": the callee may grow it and may not touch any other stack below base.
- **Output, two contracts:**
  - *Fresh result:* a function that returns a growing value builds it on a destination stack the caller names. The destination belongs to the caller: it's below the callee's base, and the caller keeps it out of scratch assignment for as long as the result is live. So returning a growing value is no copy.
  - *Append:* when a call's result goes straight into a builder (`out.append(line(r))`, where `out` is a growing value used as a builder), the compiler calls the function in append mode. It gets exclusive permission to append to that builder (a hidden grow parameter, so the overlap check covers it like any other) and the builder's remaining capacity. It writes its result just past the builder's end and returns the length written, not a second value. On success the caller moves the builder's end over those bytes; on failure the builder's end and its stack top go back to where they were. If the function can't be compiled in append mode (it reads the builder, say), the result is built on a scratch stack and copied.
- **Assignment:** inside a function, each growing local takes the lowest stack in its window that's free at that point, and gives it back at its scope's end (Goose's recipe). Two live growing values never share a stack, so neither is ever trapped under the other.
- **A worked example.** `render(rows)` returns a `Text` and calls `line(r)`, which also returns a `Text`. The bounds are part of the example, since the loop rule needs them:

  ```
  struct Row { name: Text max 60, count: Int 0..999999 }

  fn render(rows: List<Row> max 500) -> Text max 40000 {  // a fresh result, on the caller's destination D
      var out = Text.empty()           // out is the result, built on D directly
      for r in rows {
          out.append(line(r))          // line runs in append mode: it writes onto out's end, on D
      }
      return out
  }
  fn line(r: Row) -> Text max 80 {     // 60 + 2 for ": " + up to 6 digits = 68, within 80
      let name = upper(r.name)         // a temporary Text on base + 0
      return name + ": " + str(r.count)
  }
  ```

  A request handler with its first free stack at 0 calls `render` with destination 0 and base 1. `render` calls `line` in append mode on `out`, with base 1, so `upper`'s temporary goes on stack 1 and `line`'s output is written past `out`'s end on stack 0. When `line` returns, `render` moves `out`'s end over the new bytes, and stack 1 goes back to where the iteration started: one store. This entry point uses stacks 0 and 1, so N = 2, as long as `upper` and `str` use only stack 1 for scratch and write their results where they're told (their contracts say so).

  The bounds add up: 500 rows × at most 80 code points is 40,000 code points, which is `render`'s declared maximum. Reservations are in bytes, and a code point takes up to 4 bytes in UTF-8, so stack 0 needs 160,000 bytes, plus page rounding. Stack 1 needs `upper`'s result, at most 60 code points (240 bytes).
- **Passing the base:** a hidden argument by default. A function is also compiled for a constant base (its stack addresses fixed offsets from the context pointer) only when it's small or hot and called with that base; at most two copies of any function, and the compiler reports code-size growth from copies.
- **Recursion** (opt-in, on functions marked `recursive`, decided 2026-10-24): a recursive cycle may not hold a growing value across its recursive call, since that would need a stack per call; the compiler refuses it and names the value. Each recursive function's native frame size is known at build time, and every recursive call checks the native stack against a byte budget (one compare, like the data stacks); passing it fails the job. That bounds bytes, not just depth.
- Fixed values over 4 KB go on the fixed-scratch stack, never on top of a growing one.

### Loops can't quietly fill a stack

A bump stack frees nothing until its scope ends, so a careless loop can fill one: a temporary per iteration that piles up, rebuilding an outer value (`s = s + piece`) so each old copy is trapped under the new one (memory that grows with the square of the size), or appending to an outer value with no limit. The language rules out all three (decided 2026-10-24):

- **Every iteration is a scope.** Temporaries made in a loop body are freed when the iteration ends, including on `continue` and `break`. Only the iteration's own scratch goes back: the stacks of values that live outside the loop (`out` in the worked example) keep the end they've grown to, and every other stack's top returns to where the iteration started, which costs a register move each. Nothing made in an iteration survives it unless it's written into a value that lives outside the loop.
- **Results go straight to where they're kept.** `out.append(f(x))` runs `f` in append mode (see the append contract in How the compiler assigns stacks), so keeping a result costs no copy and leaves no temporary to collapse.
- **Rebuilding an outer value never traps the old one.** `s = s + piece` compiles to an append in place. Any other reassignment of an outer growing value (`acc = merge(acc, x)`) builds the new value on a scratch stack and copies it down over the old one. The memory stays bounded by two values, the old and the new, during the copy, never by the sum of all iterations; the compiler counts that two-value peak in the bounds and reports the copy in `inspect stacks`, since it costs time per iteration.
- **A value a loop keeps growing must have a bound.** Either its type says so (`List<Hit> max 10000`, `Bytes max 1 MB`, `Text max 4000`), or the loop is counted over a bounded input and each iteration's growth is bounded (`for r in rows` with `rows: List<Row> max 500`, appending a `line(r): Text max 80` each time, is 500 × 80 code points). The bound is on what each iteration adds, so a helper that formats a piece declares its own result's maximum, separators included. Without either, it's a build error that names the value and the loop, and offers both fixes. At run time, an append past a declared maximum returns a `Result` the code must handle (`out.try_append(x)`), or is proved impossible.
- **Bounds come from where data enters.** Request bodies, files, and table text fields have declared maxima (`Text max N`, `Bytes max N` on the input or column), so a bound found at the edge carries through the code. A table field declared without a maximum can still be read through a view, but copying it onto a stack inside a loop needs a bound.
- **The compiler adds it up.** From the bounds it computes each stack's worst case per entry point, which sizes reservations (N stacks per job). `inspect stacks` lists, per entry point, each stack's worst case and the lines that drive it, and every loop's growth per iteration. An entry point with something still unbounded (an untyped external call, say) is listed as such and gets the default reservation.
- **Tests can pin it:** `expect stack_peak(handler) < 2 MB` fails a test when a change raises the worst case past a budget.
- **Tools that read whole projects** bound their inputs too: a source tool declares the most files and bytes per batch it accepts, and a budget for the trees it keeps, rather than relying on the default reservation and failing.
- **Nested growing values wait:** in v1 a growing value can't contain growing values on a stack (a `List<Text>` built on a stack, a record with two growing fields). The first implementation refuses them with an error suggesting a table or builder instead. The later design keeps two compiler-assigned stacks for such a value, one for its fixed-size descriptors (`{offset, length}` per element, offsets rather than pointers) and one for the elements' bytes. An element is frozen once it's added; changing it means rebuilding it at the end and updating its descriptor. Both stacks, alignment and any temporary copy count in the bound.

### Keeping it fast

- **A context pointer, not thread-locals.** Every function takes one hidden pointer to its job's context: stack bases, tops, limits and the step budget. Hot code never looks up thread-local storage (Burin's helpers do today; that goes).
- **Stack tops in registers** (Goose's top caching): a function keeps the top of each stack it grows in a register, and writes it back only before a call that can reach that stack (or suspend), and at exits. A loop that pushes is a store, an add and one compare.
- **No aliasing between stacks:** different stacks never overlap, so LLVM knows a push to one doesn't change what's read from another. `noalias` is emitted only where it's proved: distinct stacks, or parameters the call-site rule keeps apart.
- **Freeing a scope** puts saved tops back: register moves, with memory written only at function exit.
- **No locks, no atomic operations on stacks,** since a job's stacks belong to it alone.

### Crossing threads

Nothing mutable is shared. Values cross in four ways:

1. **Queues of flat values.** A flat value is one contiguous block with no pointers in it (data inline, typed ids instead of pointers), so sending is one copy into the queue and one onto the receiver's stack. Queues are bounded rings: one producer and one consumer where possible, with no locks; many producers to one consumer for workers sending to the writer.
2. **Snapshots** of a table set (Tables across threads).
3. **Frozen tables** (below).
4. **Parallel loop inputs and results** (Parallel loops).

A typed id means a row in a table set, not a memory address, so it stays valid in any thread reading the same snapshot.

### Parallel loops

- `parallel for t in texts { … } collect`, or `parallel for i in 0..n reduce sum`: the runtime splits the work into chunks that idle workers take (work stealing: an idle worker takes chunks from a busy one's queue). Each chunk runs on stacks of its own.
- **Inputs:** the loop is scoped (the caller waits until every chunk is done), so the caller's stacks stay alive and unchanged for the whole loop. Chunks get read-only views of what the body reads from the caller (`texts` here), with no copy; the views end at the join, before the caller can change anything again. Chunks may also read the caller's pinned snapshot, which stays pinned until the join (Thread kinds and jobs).
- **The body** may have no effects, and may write only what it owns: its own scratch and its slot of the result. Reads of captured caller values are read-only views; a body that tries to write or grow a captured value is refused, whatever its effects. So there are no data races.
- **Outputs:** `collect` writes into a result buffer the caller owns, on its destination stack. When the output sizes are known up front (one value per item, fixed size) each chunk writes its slice directly. Otherwise each chunk builds its output on its own stack and the join copies the pieces in index order before those stacks are reset. `reduce` combines chunk results in a fixed tree order, whatever the scheduling, so floating-point sums come out the same on every run.
- **No nesting in v1:** a `parallel for` reached from inside another runs sequentially, so workers can't all end up waiting for work nobody can run. A worker waiting at a join runs other chunks of the same loop meanwhile.
- Small loops run sequentially below a cost threshold, so a fork never costs more than it saves.

### Tables across threads

- **One writer per table set.** Workers send change requests on a queue and get a reply (Burin's model); writes are batched.
- **Snapshot cost proportional to what changed:** a table's columns and payload are stored in fixed blocks (4,096 rows, say). The blocks hang off a small tree (a radix tree: each level indexes into the next by part of the row number). A write copies the blocks it touches and the tree nodes on the path to them, and shares everything else with the previous version. Publishing is proportional to the blocks changed, not the table size.
- **One version per table set:** every table in a set is published together under one root, so a reader never mixes one table's new rows with another's old ones. For a SQLite-backed set the writer publishes a version only after SQLite's commit succeeds; after a crash the tables are rebuilt from SQLite. In-memory tables are lost on a crash unless the program saves them.
- **Publishing and pinning safely:** the writer finishes writing a version's blocks before publishing it. Taking a pin (reading the current root and counting it) and publishing a new root happen under one short runtime lock, so a reader can never pin a root the writer is freeing; the lock covers only those few instructions, never row reads. v1 uses this lock because it's simple and obviously right; a lock-free scheme can replace it if measurements show contention.
- **Pinning:** a job pins the current root when it starts reading and unpins it when it ends or before it waits (Thread kinds and jobs): one pin per read phase, never per row or block.
- **Freeing old blocks:** readers' pins keep a version's root alive; roots and tree nodes keep blocks alive. Each tree node and block has a count of the tree nodes or roots that point to it, kept by the writer alone, so no reader ever touches it. When an old root is neither current nor pinned, the writer drops it: it decrements the counts of what it points to, and frees each node or block whose count reaches zero, recursively. A block shared with the current version keeps a count above zero and stays. This costs work proportional to what the dropped version didn't share.
- **Slow readers:** a pin lives only for a stretch of computing with no waits, and that is bounded by the job's time limit. If pinned old versions still hold more memory than a budget, the writer pauses applying writes until they're released. A live view is never invalidated.
- A table used by one thread only (a game's simulation) skips snapshots: plain arrays, no counting.

### Frozen tables: big shared data built in parallel

Many programs build a large structure once and then read it from many threads: a compiler's syntax trees (the TypeScript compiler's Go rewrite parses files in parallel, then several type-checker threads read the same trees), a game's level, a search index. Funnelling every node through one writer would be far too slow, and stacks die with their job. So (decided 2026-10-24):

- **Build:** a job creates a *builder* table that only it owns: no writer, no snapshot, plain arrays. One file's syntax-tree nodes, for example, with child links as typed ids and source text as `{offset, length}` into the builder's payload blocks. Data-oriented compilers (Zig, Carbon) already store trees this way: compact and fast to walk.
- **Freeze:** `freeze b` ends the builder and turns its blocks into a read-only partition, published as one pointer, with no copy. The type system then refuses writes to it, and the old builder name is gone.
- **Group:** a batch root lists the partitions (one per file). A frozen id is 64 bits: a 32-bit partition number and a 32-bit row. Frozen rows are never deleted, so no generation is needed. A node in file 3 can refer to a declaration in file 7.
- **A batch is a token made first:** `let b = batch()` creates a unique, scoped batch token before any builder exists. Builders are created from it (`b.builder(Node)`), each given its partition number up front, so ids are final while they're built and freezing renumbers nothing.
- **Ids can't cross batches:** the id's type names its batch token (`b.Node.Id`), and each `batch()` call makes a distinct token, even in a loop or in two calls of one function. So mixing ids from two batches is a build error, and since the token is scoped, ids can't escape it (they can't be stored in a table that outlives it or returned from its scope). A lookup still checks the partition and row against the batch's sizes (one compare each).
- **References between partitions while building:** a builder can refer to its own rows by id at once. A reference to a row in another file isn't known until that file is parsed, so it's stored as a name and resolved in a pass after freezing (as compilers resolve names after parsing), which writes the found ids into a job-owned table of resolutions rather than into the frozen rows.
- **Read:** jobs pin the batch root once, as with snapshots; functions take read-only views of rows, text and lists as parameters, with no copying and no counting per node.
- **Lifetime:** a frozen batch lives until the scope that created it ends (for example "check this project") and no job pins it; then its blocks are freed in bulk.
- **Per-job caches:** each reading job keeps its own job-owned tables for what it computes (the TypeScript checkers each keep their own type caches the same way).

Still off the table: many threads writing into one shared structure (a global interner that stores each distinct type once has to live on a writer, or be per-thread and merged after the phase); freezing part of a structure while changing the rest; pointers from a frozen table into a job's stack; counting per node.

### Targets

| Operation | Target |
| --- | --- |
| Push in a loop | under 1 ns, no atomic operations |
| Free a scope | under 5 ns, whatever it held |
| Start a job (stack set from the pool) | under 200 ns |
| Suspend and resume a job | under 1 µs |
| Send a 64-byte value through a queue | under 100 ns |
| Parallel loop overhead (fork and join) | under 5 µs |
| Independent chunks of one parallel loop, 4 cores | at least 3.5× one core (hardware reported with every timing) |
| Publish a snapshot | proportional to blocks changed, not table size |
| Freeze a builder | constant, whatever its size |

### Open questions

- How many copies code size can bear, and when constant-base copies pay.
- How large N grows in programs that use many libraries.
- Parallel loops inside a game tick, keeping ticks deterministic and within their time budget.
- The block size for table snapshots.
- Whether jobs should ever move between workers (better balance, but stacks would then need to be safe to hand over).

*(Diagram in the shared Claude Doc: threads · workers with their own stacks, one writer, snapshots.)*

Workers grow and free their jobs' stacks without locks; changes go to the writer through queues, and every job reads a pinned snapshot. A parallel loop's chunks run on these same workers.

## Types, and refinement types

Refinement types are the design's best lever: one declaration serves correctness, efficiency and every layer at once, if they stay small enough to check quickly.

**The base:** values with no null; `Option` and `Result`; records; enums with payloads and exhaustive `match`; generics with static traits; newtypes (a `UserId` is not an `Int`). Arithmetic is checked: an overflow is a failure, and wrapping is spelled `+%`.

**Failures** that aren't values: an overflow, a divisor of 0, an index the compiler couldn't prove in range and that turns out not to be, a data stack or the native-stack budget exhausted, the step budget spent (an unbounded loop's limit), a time limit passed. Each fails the job, as a stack limit does (see Memory): the job ends with an error carrying the source line. A function returning plain `T` therefore never returns a half-made value.

**What failing a job does,** in this order, so nothing can touch memory after it's reused:

1. Stop scheduling the job: no more of its code runs.
2. Cancel its pending I/O and its unstarted parallel-loop chunks; wait until running chunks have stopped (a chunk checks for cancellation at its step-budget checks) and the event loop has confirmed no I/O will write into the job's buffers.
3. Discard its uncommitted work: a change batch not yet sent, or sent and not yet applied (the writer drops batches from failed jobs). Batches the writer already committed stay committed (decided 2026-10-24, see Transactions).
4. Release its snapshot pin and any frozen batches or builders it owns.
5. Reset its stacks and return the stack set to the worker's pool.
6. Report the failure: to the client (a 500 for a request), to the log, and to the parent if it was a parallel-loop chunk, which fails the parent job with the chunk's error. Code that wants to handle one of these locally uses the checked form that returns `Option` (`checked_add(a, b)`, `a.get(i)`), or a refinement that proves the failure can't happen.

**Text and bytes** (decided 2026-10-24): `Text` is always valid UTF-8, and `Bytes` is raw data (DEFLATE's output, files, the network). Going from `Bytes` to `Text` is a checked step that returns `Result`. Text lengths count Unicode code points (what a person would call characters, roughly); byte lengths are written on `Bytes`, or as `Text bytes max N` when a byte budget is what matters.

**Refinements** are a type plus a predicate the compiler understands, a closed set kept decidable:

| Kind | Written | Example use |
| --- | --- | --- |
| Range | `Int 0..100`, `Int >= 0` | quantities, percentages, indexes |
| Length | `Text max 80`, `List<T> 1..20` | names, bounded lists |
| Membership | `Text in ["low", "high"]`, an enum | states, options |
| Pattern (a regular-language subset) | `Text matches slug` | slugs, codes, emails as syntax only |
| Index | `Index(a)`, meaning `0 <= i < len(a)` | array positions with no bounds check |
| Linear relation between fields | `invariant start <= end` | intervals, budgets |

**How they are checked:**

- Values enter a refined type at a boundary only: parsing input, reading a column, or an explicit `check`, which returns `Result`. Inside, operations keep or prove the refinement. Parse, don't validate.
- The compiler infers refinements by interval and sign analysis (Burin's sign analysis is a first version): `x: Int 0..100` plus `y: Int 0..100` is `Int 0..200`, with no overflow check.
- Where it can't prove a refinement it asks for one of three things: a `check` (a runtime test with an error to handle), a stronger parameter type, or a rewrite. It never assumes silently.
- A fact about a growing value's length (`i` is an `Index(a)`) holds until something can change that length: a grow of `a` itself, or a call that takes `a` in grow mode. The compiler sees both, since references are only parameters and two parameters never overlap when one changes; after either, the fact is gone and the index must be proved again.
- Field relations and table invariants go to a solver (Z3, as crudspec does) only in a separate deep check, so ordinary builds stay fast.

**What refinements buy, per goal:**

- *Correct:* bad values can't exist past the boundary; slips like a negative stock are build errors.
- *Efficient:* proved ranges become LLVM facts: an `Index(a)` carries no bounds check, and a sum of bounded values none for overflow. The DEFLATE work showed this is where checked code loses to C.
- *Easy:* one declaration replaces validation code in the form, the API, the database and the tests (next section).

**What to avoid:** full dependent types and arbitrary predicates (slow checking and baffling errors, as Liquid Haskell and F\* show), and refinements on everything by default. They stay opt-in on the fields and parameters where they say something.

## One declaration, every layer

crudspec's best idea generalized: a type, a rule or a permission is declared once, and the compiler projects it into every layer that needs it, so the layers can't disagree.

In crudspec today a field's size carries through: `title: Text max 80` is a CHECK in SQLite, a refusal in the action, `maxlength` on the form and `maxLength` in the agent's schema. The general version treats each layer as a projection of the same declaration:

| Declaration | Storage | Wire (JSON, CLI, forms) | UI | Agent API | Tests | Compiler |
| --- | --- | --- | --- | --- | --- | --- |
| `Text max 80` (code points) | CHECK with the runtime's own SQLite function that counts every code point (SQLite's `length()` stops at the first zero character, which is valid text) | rejected on parse | a code-point counter that blocks submit (not `maxlength`, which counts UTF-16 units) | `maxLength` (JSON Schema counts code points) | boundary cases 0, 80, 81, with characters outside the basic plane and a zero character | buffer bound known (at most 4 bytes per code point) |
| `Bytes max 4096` | CHECK on `length()` of a blob (exact for blobs) | the decoded byte count is checked | a file-size check | `maxLength` on the base64 text, only as a first filter (4,096 and 4,098 bytes encode to the same length); the server checks decoded bytes | 0, 4096, 4097 bytes | buffer size known |
| `Int 0..100` | CHECK range | rejected on parse | `min`/`max` input | `minimum`/`maximum` | -1, 0, 100, 101 | no overflow check |
| enum `State` | CHECK IN | one of the names | a select | `enum` | every case | exhaustive `match` |
| `invariant start <= end` | CHECK on the row | rejected on parse | the form's error | described in the schema | generated pairs | solver proof per writer |
| permission `read Item: owner == actor` | WHERE on queries | 404, not 403 | hidden rows and links | the tool can't see them | an outsider scenario | change review flags widening |
| error `Result<_, OutOfStock>` | none | status 409 + code | a message | an error code | the failing path | must be handled |
| effect `db.write` | transaction | none | none | marked as a write tool | effect assertion | capability required |

**Rules for the projections:**

- A projection is generated only where the layer's rule means the same thing as the declaration. Where a layer counts differently (HTML's `maxlength` counts UTF-16 units, not code points), the generated code checks it the declaration's way instead of using the layer's near-miss.
- Layers are compiler back ends, not libraries, so each projection is checked. A form can't drop a field an action needs; a page can't show a row a permission hides.
- A layer may override how a declaration looks (a label, a message, a widget), attached to the same declaration and flagged by the change review. It may not override what it means.
- The projections are generated, never hand-edited (crudspec's rule). Hand code goes in typed extension functions with declared effects.
- Tests come out too: every refinement yields boundary cases, every enum its cases, every permission an outsider scenario. These run with the scenarios.

This is also where refinement types pay twice: the same `Int 0..100` that a form enforces is the fact that removes an overflow check.

## Effects and capabilities

What a function may touch is part of its type, inferred across calls, and granted only by the program's entry point (Hobthrush's model).

- A closed effect set: `db.read`, `db.write`, `fs.read`, `fs.write`, `net`, `clock`, `random`, `env`, `secret`, `log`, `spawn`. No effects means pure.
- **Pure** means deterministic (the same inputs give the same result) with no effects. A pure function may still change or grow what it's handed through a write or grow parameter; those modes are part of its type, so callers and the compiler see them.
- **Cacheable** is narrower than pure: no effects, every parameter read-only, and a result the function owns. Only cacheable functions may be cached, evaluated at compile time or used by cached page pieces, since skipping a call to one changes nothing but the time taken. A pure function that appends to its caller's list isn't cacheable: reusing a saved result would skip the append.
- **Reading a snapshot is pure,** because the snapshot is an input: a function that reads tables takes the pinned snapshot as a read-only parameter (passed implicitly, like the context pointer), and its result depends on that version. `db.read` is the effect of reading the live database outside a snapshot (a SQLite query that sees the latest commit). Parallel loop bodies and cached pieces may read the snapshot; a cache keys its entries by the snapshot's version, so a cached result never outlives the data it came from.
- Effects are inferred. A function may state an upper bound; exceeding it is an error that shows the shortest call path to the effect.
- Capabilities are values the entry point hands down (`Clock`, `Db`, `Http`), granted in the package manifest. A library can't reach the network unless a caller passes it a capability.
- Burin's rule "pages call only pure functions" falls out of cacheability.
- Time and randomness come only through capabilities, so tests and replays can supply fixed ones.
- C functions declare their effects at the binding (`fn crc(b: Bytes) -> Int = c "crc32_z" from "z" effects none`). The declaration is trusted, and the audit report lists it as such.
- `inspect effects` and the change review report effect widening, like permission widening.

## Correctness tools

Testing is part of the language, because measured over four weeks, scenarios and reference checks caught bugs and type rules alone mostly didn't.

- **`test` blocks with `expect` steps** (AgentLang's form): several per test, `let` between them, both sides shown on failure.
- **Scenarios:** a named sequence of actions by named actors with expected outcomes, written against the app's own vocabulary. They're the language's integration tests and the change review's evidence.
- **Reference checks:** `check fast == reference` holds an optimized function to a plain one, over generated inputs and the refinements' boundary cases. Burin's interpreter-versus-native, Rust-versus-SQL and fast-path-versus-fresh-render checks become one construct.
- **Golden outputs:** a test may pin bytes (a page, a file); `accept` updates them after a reviewed diff.
- **Invariants** on tables are checked on every write at run time, and optionally proved for every writer by the deep check.
- **Determinism:** fixed iteration order, and time and randomness only through capabilities. Any failing run is replayed from its inputs; a game tick or a server's write batch is a recorded step.
- **Generated cases:** boundary values from refinements, every enum case, an outsider for every permission (previous section).
- **Fuzzing:** random inputs within refinements, and random action sequences against the invariants.

## Performance model

The compiler doesn't try to out-optimize LLVM; it tells LLVM what the language knows and does early what can be done early.

- **Facts for LLVM:** refinements and inferred ranges as `assume` and `range` attributes, non-negative values, `noalias` where it's proved (distinct stacks, parameters the call-site rule keeps apart), `smin`/`smax` for `min`/`max`, plain `add nsw` (an add LLVM may assume doesn't overflow) where overflow is ruled out. Every fact comes from a proof; none is assumed. In Burin these took DEFLATE from 0.70x to 0.85x of C (0.89x after later work).
- **Loops that provably end** carry no step budget: counted up or down, or any counted part of an `and`. Long ones still poll for cancellation every few thousand iterations (one load and compare), so deadlines hold.
- **Compile-time evaluation:** statements that depend only on constants run in the compiler; their tables become read-only data.
- **Layout:** tables as one array per field; fixed-size data inline in its column, variable-size data in the table's payload blocks; enums sized to their largest case; typed ids 64 bits in v1 (narrower ids would weaken the generation check, so they wait for measurements).
- **No steady-state allocation:** stacks and table storage are reused; a test asserts zero allocations on chosen paths, as Burin's hot-path test does.
- **Load what is used:** queries and loads guarded by the conditions around their uses; a per-request piece rendered once per page. Burin's +27% to +50%.
- **Work at write time where reads dominate:** derived values and rendered pieces kept up to date by the writer, behind the same purity rules (a library, as Burin's caching becomes).
- **One release pipeline:** LLVM with cross-language LTO, so the runtime's helpers inline into generated code.

## Development experience

One compiler target, LLVM, for development and release alike: no JIT, no interpreter, no live swap, so nothing can drift between two back ends. A small edit is running again within 3 s (decided 2026-10-24).

- **Development builds:** LLVM at `-O1`, no LTO, one object file per module cached by a hash of its source, its dependencies' interfaces, the generic copies it contains (each per-type copy is compiled into the module that first needs it, and its key includes the generic's source), and whatever compile-time evaluation read, so a one-function change rebuilds one object and relinks. Target: 3 s from save to running on a Campfire-sized program; release builds (`-O3`, LTO) under 30 s.
- **Restart, not swap:** a change restarts the program. Table data in SQLite survives; a changed table's migration, planned from the diff (crudspec), runs at start.
- **What you test is what ships:** tests run on the same code generator as release, at the development optimization level, and in release mode in CI.
- **Compile-time evaluation** covers some of what a REPL would: constant code runs in the compiler.
- **One way to write each thing:** small syntax, inferred types, no imports inside a package (an app or library is a directory), one formatter.
- **Errors that name the fix:** "did you mean" for names, keywords and attributes, the error at the slip's own line. Their quality is measured by seeding slips, as crudspec's mutation harness does (99% of misspelled names caught there).
- **For agents:** `inspect` reports in JSON (API, effects, refinements, tables, call graph), and a change review that lists what a change widens: effects, permissions, refinements loosened, invariants dropped.
- **Editor:** a language server from the start, sharing the compiler's code (Stasis's VS Code extension is the model).

## Concurrency and interop

Threads share nothing mutable; C is reachable through typed bindings that declare their effects.

**Concurrency**

- Threads, data stacks, queues, snapshots and parallel loops are designed in Threads and data stacks, above.
- No locks in the language: nothing mutable is shared, so data races can't happen.
- I/O waits suspend the job, and an event loop per worker resumes it (Thread kinds and jobs): no `async` colouring in source.

**Interop**

- C functions bind with a declared C prototype and effects. The ABI (the binary calling rules both sides follow) is the platform's C calling convention, with these mappings:
  - Integers as 64-bit (or the declared C width), `Bool` as a byte, floats as `double`.
  - `Text` and `Bytes` as a pointer and a length, valid only during the call; C must not keep the pointer.
  - Records as a pointer to a C struct with the same field order and C's alignment rules; enums as a 32-bit tag followed by the largest payload.
  - Results that grow (text, bytes) written through a runtime buffer function the call is handed (Burin's and AgentLang's ABI).
  - Errors as a return code the binding maps to `Result`; C never returns `none` by convention.
  - No unwinding across the boundary: a C++ exception or Rust panic that reaches it aborts the process, and the binding generator wraps Rust functions to catch panics.
- Rust functions bind through the same C ABI and inline under LTO.
- Bindings to C libraries (zlib, SQLite, crypto) are how CPU-critical or security-critical pieces get done: no home-made crypto.
- Foreign code is trusted; the audit report says so plainly.

## Validation plan and kill criteria

The core is proved on four narrow programs, one per use plus compute, before any widening, each against a strong baseline. Every result records the source revision, the exact command, the machine, peak memory and build time.

| Program | Baseline | Target | Kill if |
| --- | --- | --- | --- |
| DEFLATE and CRC-32 (compute) | a C version with precomputed tables, clang -O2, on Silesia's dickens (10.2 MB), one core, median of 9 | throughput 0.9x of C or better | under 0.75x after the facts work |
| Parallel tool: parse and check a source corpus (builders, frozen tables, parallel loops) | a Rust version with the same algorithm and thread count | 0.9x of Rust's time or better, and 3x or more on 4 cores over 1 | under 0.7x of Rust, or under 2.5x scaling on 4 cores |
| Campfire-class server (tables in SQLite, pages, live updates) | Burin today; the optimized Rust port | Burin's pages/s within 10%, memory within 1.2x | under 0.7x of Burin, or over 2x its memory |
| Waiting jobs (the same server with 10,000 requests suspended on a slow outside call, from fresh and from previously busy stack sets, with snapshots pinned by the running ones) | the Rust port with the same load | stated ceilings met: committed memory under 1 GB for the 10,000, address reservations within admission limits, excess requests answered with 503 | over 2x the Rust port's memory, or any crash or unbounded growth |
| Game simulation (tables in memory, ticks) | Stasis ahead-of-time | equal speed; a small edit running again in 3 s | slower than 0.8x |
| Seeded slips (mutation harness) | crudspec's numbers | 99% of misspelled names caught at their line | under 95% |
| Refinements on the four programs | the same programs without them | at least half of bounds and overflow checks gone; no slower build than 1.2x | builds over 2x slower, or no checks removed |
| Agent changes (scenario-scored feature requests) | the same requests in Rust | equal or better correctness, fewer exchanges | worse on both (AgentLang's outcome) |

The agent study follows the lessons of AgentLang's: the outcome is scored by scenarios the agent never sees, with fresh agents and equal briefs on both sides.

## Risks, open questions and first steps

The largest risk is scope: a general-purpose language is how Hobthrush ended up building everything at once. The first steps happen in this language's own folder (D:\code\next-lang, a working name), copying from Burin's helper compiler, which already reaches 0.89x of C, without depending on Burin.

**Risks**

- *Typed ids instead of pointers* make trees and linked structures index-based. That's efficient, but needs library types (pools, arenas, graphs) so it doesn't feel clumsy.
- *Refinement errors* can baffle ("can't prove i < len(a)"). Each error must name what would prove it: a `check`, a parameter type or a loop bound.
- *Projections to every layer* tempt layer-specific special cases. Overrides change looks, never meaning.
- *Solver time* (Z3) must stay out of ordinary builds.

**Decided (2026-10-24)**

- Recursion is opt-in: only functions marked `recursive` may call themselves, directly or through a cycle. A recursive cycle can't hold a growing value across its recursive call, and its native stack use is checked against a byte budget; going past it fails the job. Everything else stays recursion-free, so stack assignment stays simple.
- Two types for text and bytes: `Text` (always valid UTF-8, lengths in code points) and `Bytes`.
- Generics are copied per type (as Rust and C++ do): full speed, and LLVM sees concrete types, at a cost in code size and build time that the 3 s target has to absorb.
- Servers, games and tools weigh equally; the validation has a program for each.
- Jobs can wait: I/O suspends a job, which keeps its own stacks, and the worker runs others meanwhile.
- Running out of a data stack (or another runtime failure) fails the job, not the program; no `Result` on every push.
- v1 targets 64-bit platforms only; WebAssembly and 32-bit come later.
- Build-then-freeze tables for large data shared read-only across threads.
- A value a loop keeps growing must have a bound the compiler knows, and each iteration's temporaries are freed when it ends.
- A failed job discards only its uncommitted batch; committed batches stay, and `transaction { }` groups changes that must succeed together.

**Open questions**

- Can development builds hold 3 s as programs grow, with per-module caching alone, or will they need a faster code generator for `-O0` (LLVM's FastISel, or splitting modules finer)?
- The language's name (the folder's is a working one).

**First steps**

1. Tables and typed ids: in-memory tables with generation-checked ids, one array per field.
2. Goose-style stack assignment for growing values, replacing the helper arena: stack contracts (fresh-result and append), iteration scopes, bounds per entry point; `push`, text built from pieces, `out_byte` as a store and bump. Nested growing values are refused at first.
3. Refinements on parameters and fields (range, length, membership, index), inferred through the sign analysis and emitted as LLVM facts. Measured on DEFLATE.
4. `check fast == reference` and `test` blocks with `expect`.
5. Effects inferred on helpers, with the call path in errors.
6. Builders, `freeze` and parallel loops, measured on the parallel tool.
7. The four-program validation above; then decide on widening.
