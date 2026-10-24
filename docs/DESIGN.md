# A general-purpose language: correct, easy, efficient


> Source: the shared Claude Doc https://claude.ai/artifact/AfD3gnVW8QqwrVXomjv48H (it has the two diagrams). From here on this file is the working copy, refined with Codex.
Oct 23, 2026 · @Ben Maddox

## Goals and non-goals

One language that is hard to get wrong, quick to work in, and within about 10% of C on CPU and memory, for servers, games and tools. Each goal has a test, not an adjective:

- **Correct:** a wrong program fails at build time or in a test that comes with the language, not in production. Measured by seeded slips caught, scenarios passing, and fast-versus-reference checks.
- **Easy:** a small edit is running again within 3 s, a release builds in under 30 s, and every error names the fix. Measured by edit-to-running time and the mutation harness's "did you mean" rate.
- **Efficient:** no garbage collector, no allocation in steady state, compute within 0.9x of C, servers within 1.2x of the optimized Rust port's memory. Measured on DEFLATE, a Campfire-class server and a game simulation.

Non-goals for the first version:

- Full dependent types or proofs of arbitrary properties (refinements stay decidable, see Types).
- Pointer graphs with arbitrary aliasing; long-lived links are typed ids.
- Replacing Burin or the other languages: Burin continues as its own web language, and this is a separate project in its own folder that borrows their ideas and code.
- A package ecosystem, async runtime or governance model before the core proves itself.

## Evidence from the six languages

The design keeps what was measured to work in four weeks of building six languages, and drops what was measured not to.

| Idea | From | Evidence | Verdict |
| --- | --- | --- | --- |
| Scenarios, golden outputs, fast-versus-reference checks | crudspec, AgentLang, Burin | Scenarios caught 86% of seeded bugs; the checker's main rule alone, 9% (crudspec H1) | Keep, as language features |
| Work done before run time | Burin, AgentLang | Constant tables: CRC-32 on 64 B 683 to 75 ns; write-time pieces: Campfire 54k to 69k pages/s | Keep |
| Facts handed to LLVM, not a home-made optimizer | Burin helpers | DEFLATE 0.70x to 0.89x of clang -O2 | Keep |
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
- Rows refer to each other by typed ids, `Item.Id`: a slot and a generation counter. A stale id is detected (none), never a dangling pointer.
- A table is in memory or backed by SQLite with the same syntax; queries on a SQLite table compile to SQL.
- Invariants are declared on tables and checked on every write (see Correctness).
- One writer per table set changes it. Readers on other threads read an immutable snapshot, counted once per read, never per row (Burin's model).

**Stacks** hold temporaries.

- Each thread has N stacks, each a large reserved address range with a bump pointer. N is computed by the compiler.
- At most one growing value per stack, always on top of it (Goose's rule). The compiler picks each growing value's stack: the lowest index free at that point. So growth is a pointer moving up, nothing moves, and positions stay valid.
- Fixed-size values sit in registers or the native stack; small arrays too (up to 4 KB, as Burin's helpers do).
- A scope's memory is freed by setting its stacks back: one store each. Kept pages stay mapped for the next call (time over memory).
- Growing past a stack's end is a failure value (none or an error), checked with one predictable compare, never a crash.

**References** exist only as parameters: a function may read, write or grow what it is handed, but cannot store or return a reference. So no lifetime annotations are needed, and Goose's "roots" check reduces to a call-graph rule.

Between the two: a value moves from a stack into a table by copy (`create Item { … }`), and from a table onto a stack by reading fields. Data stays inline: a record's text is in its row, not behind a pointer.

*(Diagram in the shared Claude Doc: memory model · tables, snapshot, per-thread stacks.)*

The writer changes tables and publishes snapshots that readers share; every thread computes on its own stacks, freed in bulk.

## Threads and data stacks

A fixed set of threads, one per core, each owning N data stacks that only it touches. So the common operations (push, free a scope, read a table) take no locks and no atomic operations, and nothing mutable is shared.

### Thread kinds

- **Workers,** one per core, pinned. Each runs requests, jobs or game ticks to completion, and does its own I/O through an event loop, as Burin's workers use mio. There's no thread per request and no `async` in source.
- **The writer,** one per table set. It applies change batches in order and publishes snapshots (Burin's model).
- **Parallel loops** borrow the workers (fork and join) rather than starting threads.
- The thread count is fixed at start (configured; the number of cores by default).

### N stacks per thread

- N is computed at build time: the most growing values live at once along any call chain from any entry point (a request handler, a job, a tick, a parallel loop's body), plus one stack for fixed scratch over 4 KB.
- Each stack is a reserved address range with a guard page at its end. Pages are committed on first touch and kept between calls (time over memory). They're given back only when a stack's high-water mark stays far above its use, or on request.
- Address space is plentiful on 64-bit: 16 threads × 16 stacks × 4 GB reserved is 1 TB of the 128 TB a process can address, and only touched pages use memory.
- Growing past a reservation is a failure value, found by one predictable compare, never a crash.
- Where address space can't be reserved (WebAssembly, 32-bit), stacks are chunked and copy on growth: same meaning, slower growth.

### How the compiler assigns stacks

- Goose's recipe: walk the call graph from each entry point. Each growing value takes the lowest stack index free at that point, and gives it back at its scope's end. A growing value a function returns is built directly on the stack its caller chose.
- A callee learns which stacks it may use in one of two ways: specialized per base index (constant offsets, for small or hot functions), or a hidden base argument (for the rest, so code doesn't multiply). At most two copies of any function.
- Recursion, if allowed: a recursive cycle can't hold a growing value across a recursive call, since that would need a stack per call. Such values go on the native stack, or the cycle is refused.
- Fixed values over 4 KB go on the fixed-scratch stack, never on top of a growing one.

### Keeping it fast

- **A context pointer, not thread-locals.** Every function takes one hidden pointer to its thread's context: stack bases, tops, limits and the step budget. Hot code never looks up thread-local storage (Burin's helpers do today; that goes).
- **Stack tops in registers** (Goose's top caching): a function keeps the top of each stack it grows in a register, and writes it back only before a call that can reach that stack, and at exits. A loop that pushes is a store, an add and one compare.
- **No aliasing between stacks:** different stacks never overlap, so LLVM knows a push to one doesn't change what's read from another.
- **Freeing a scope** puts saved tops back: register moves, with memory written only at function exit.
- **No locks, no atomic operations on stacks,** since a stack belongs to one thread.

### Crossing threads

Nothing mutable is shared. Values cross in three ways:

1. **Queues of flat values.** A value is one contiguous block (data inline, typed ids instead of pointers), so sending is one copy into the queue and one onto the receiver's stack. Queues are bounded rings: one producer and one consumer where possible, with no locks; many producers to one consumer for workers sending to the writer.
2. **Snapshots.** Readers get the current immutable snapshot of a table set, counted once per request, never per row.
3. **Parallel loop results** (next).

A typed id means a row in a table set, not a memory address, so it stays valid in any thread reading the same snapshot.

### Parallel loops

- `parallel for t in texts { … } collect`, or `parallel for i in 0..n reduce sum`: the runtime splits the work into chunks that idle workers take (work stealing). Each chunk runs on its worker's own stacks.
- The body must be pure except for its own result, and may read snapshot tables. The effect system checks this, so there are no data races.
- **Deterministic results:** `collect` joins chunk outputs in index order, and `reduce` combines in a fixed tree order, whatever the scheduling. Floating-point sums come out the same on every run.
- Each chunk's output is built on its worker's stack, then copied once into the caller's destination.
- Small loops run sequentially below a cost threshold, so a fork never costs more than it saves.

### Tables across threads

- One writer per table set. Workers send change requests on a queue and get a reply (Burin's model); writes are batched.
- **Snapshot cost proportional to what changed:** a table's columns are stored in fixed blocks of rows (4,096, say). A write copies only the blocks it touches, and a snapshot is an array of block pointers, counted per block. This replaces Burin's copy of the whole index on every write.
- A table used by one thread only (a game's simulation) skips snapshots: plain arrays, no counting.

### Targets

| Operation | Target |
| --- | --- |
| Push in a loop | under 1 ns, no atomic operations |
| Free a scope | under 5 ns, whatever it held |
| Send a 64-byte value through a queue | under 100 ns |
| Parallel loop overhead (fork and join) | under 5 µs |
| Independent work on 4 cores | at least 3.5× one core |
| Publish a snapshot | proportional to blocks changed, not table size |

### Open questions

- Specialization or hidden base as the default, and how many copies code size can bear.
- How large N grows in programs that use many libraries.
- Parallel loops inside a game tick, keeping ticks deterministic and within their time budget.
- The block size for table snapshots, and whether readers on a hot table pay for counting per block.

*(Diagram in the shared Claude Doc: threads · workers with their own stacks, one writer, snapshots.)*

Workers grow and free their own stacks without locks; changes go to the writer through queues, and every worker reads the writer's latest snapshot. A parallel loop's chunks run on these same workers.

## Types, and refinement types

Refinement types are the design's best lever: one declaration serves correctness, efficiency and every layer at once, if they stay small enough to check quickly.

**The base:** values with no null; `Option` and `Result`; records; enums with payloads and exhaustive `match`; generics with static traits; newtypes (a `UserId` is not an `Int`). Arithmetic is checked: an overflow is a failure, and wrapping is spelled `+%`.

**Refinements** are a type plus a predicate the compiler understands, a closed set kept decidable:

| Kind | Written | Example use |
| --- | --- | --- |
| Range | `Int 0..100`, `Int >= 0` | quantities, percentages, indexes |
| Length | `Text max 80`, `List<T> 1..20` | names, bounded lists |
| Membership | `Text in ["low", "high"]`, an enum | states, options |
| Pattern (a regular-language subset) | `Text matches slug` | slugs, codes, emails as syntax only |
| Index | `Int < len(a)` | array positions with no bounds check |
| Linear relation between fields | `invariant start <= end` | intervals, budgets |

**How they are checked:**

- Values enter a refined type at a boundary only: parsing input, reading a column, or an explicit `check`, which returns `Result`. Inside, operations keep or prove the refinement. Parse, don't validate.
- The compiler infers refinements by interval and sign analysis (Burin's sign analysis is a first version): `x: Int 0..100` plus `y: Int 0..100` is `Int 0..200`, with no overflow check.
- Where it can't prove a refinement it asks for one of three things: a `check` (a runtime test with an error to handle), a stronger parameter type, or a rewrite. It never assumes silently.
- Field relations and table invariants go to a solver (Z3, as crudspec does) only in a separate deep check, so ordinary builds stay fast.

**What refinements buy, per goal:**

- *Correct:* bad values can't exist past the boundary; slips like a negative stock are build errors.
- *Efficient:* proved ranges become LLVM facts: an index with `Int < len(a)` carries no bounds check, and a sum of bounded values none for overflow. The DEFLATE work showed this is where checked code loses to C.
- *Easy:* one declaration replaces validation code in the form, the API, the database and the tests (next section).

**What to avoid:** full dependent types and arbitrary predicates (slow checking and baffling errors, as Liquid Haskell and F\* show), and refinements on everything by default. They stay opt-in on the fields and parameters where they say something.

## One declaration, every layer

crudspec's best idea generalized: a type, a rule or a permission is declared once, and the compiler projects it into every layer that needs it, so the layers can't disagree.

In crudspec today a field's size carries through: `title: Text max 80` is a CHECK in SQLite, a refusal in the action, `maxlength` on the form and `maxLength` in the agent's schema. The general version treats each layer as a projection of the same declaration:

| Declaration | Storage | Wire (JSON, CLI, forms) | UI | Agent API | Tests | Compiler |
| --- | --- | --- | --- | --- | --- | --- |
| `Text max 80` | CHECK length | rejected on parse | `maxlength`, counter | `maxLength` | boundary cases 0, 80, 81 | buffer size known |
| `Int 0..100` | CHECK range | rejected on parse | `min`/`max` input | `minimum`/`maximum` | -1, 0, 100, 101 | no overflow check |
| enum `State` | CHECK IN | one of the names | a select | `enum` | every case | exhaustive `match` |
| `invariant start <= end` | CHECK on the row | rejected on parse | the form's error | described in the schema | generated pairs | solver proof per writer |
| permission `read Item: owner == actor` | WHERE on queries | 404, not 403 | hidden rows and links | the tool can't see them | an outsider scenario | change review flags widening |
| error `Result<_, OutOfStock>` | none | status 409 + code | a message | an error code | the failing path | must be handled |
| effect `db.write` | transaction | none | none | marked as a write tool | effect assertion | capability required |

**Rules for the projections:**

- Layers are compiler back ends, not libraries, so each projection is checked. A form can't drop a field an action needs; a page can't show a row a permission hides.
- A layer may override how a declaration looks (a label, a message, a widget), attached to the same declaration and flagged by the change review. It may not override what it means.
- The projections are generated, never hand-edited (crudspec's rule). Hand code goes in typed extension functions with declared effects.
- Tests come out too: every refinement yields boundary cases, every enum its cases, every permission an outsider scenario. These run with the scenarios.

This is also where refinement types pay twice: the same `Int 0..100` that a form enforces is the fact that removes an overflow check.

## Effects and capabilities

What a function may touch is part of its type, inferred across calls, and granted only by the program's entry point (Hobthrush's model).

- A closed effect set: `db.read`, `db.write`, `fs.read`, `fs.write`, `net`, `clock`, `random`, `env`, `secret`, `log`, `spawn`. No effects means pure.
- Effects are inferred. A function may state an upper bound; exceeding it is an error that shows the shortest call path to the effect.
- Capabilities are values the entry point hands down (`Clock`, `Db`, `Http`), granted in the package manifest. A library can't reach the network unless a caller passes it a capability.
- Pure functions are what caches, compile-time evaluation and cached page pieces may use. Burin's rule "pages call only pure functions" falls out of this.
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

- **Facts for LLVM:** refinements and inferred ranges as `assume` and `range` attributes, non-negative values, `noalias` on stack and arena arrays, `smin`/`smax` for `min`/`max`, plain `add nsw` where overflow is ruled out. In Burin these took DEFLATE from 0.70x to 0.89x of C.
- **Loops that provably end** carry no step budget: counted up or down, or any counted part of an `and`.
- **Compile-time evaluation:** statements that depend only on constants run in the compiler; their tables become read-only data.
- **Layout:** tables as one array per field; data inline in its row; enums sized to their largest case; typed ids 32 bits where a table's bound allows.
- **No steady-state allocation:** stacks and table storage are reused; a test asserts zero allocations on chosen paths, as Burin's hot-path test does.
- **Load what is used:** queries and loads guarded by the conditions around their uses; a per-request piece rendered once per page. Burin's +27% to +50%.
- **Work at write time where reads dominate:** derived values and rendered pieces kept up to date by the writer, behind the same purity rules (a library, as Burin's caching becomes).
- **One release pipeline:** LLVM with cross-language LTO, so the runtime's helpers inline into generated code.

## Development experience

One compiler target, LLVM, for development and release alike: no JIT, no interpreter, no live swap, so nothing can drift between two back ends. A small edit is running again within 3 s (decided 2026-10-24).

- **Development builds:** LLVM at `-O1`, no LTO, one object file per module cached by a hash of its source and its dependencies' interfaces, so a one-function change rebuilds one object and relinks. Target: 3 s from save to running on a Campfire-sized program; release builds (`-O3`, LTO) under 30 s.
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
- Async I/O lives in the runtime (an event loop per worker), not as `async` colouring in source.

**Interop**

- C functions bind with a declared C prototype and effects: numbers as 64-bit integers, text and bytes as pointer and length, results written through the runtime's buffer (Burin's and AgentLang's ABI).
- Rust functions bind through the same C ABI and inline under LTO.
- Bindings to C libraries (zlib, SQLite, crypto) are how CPU-critical or security-critical pieces get done: no home-made crypto.
- Foreign code is trusted; the audit report says so plainly.

## Validation plan and kill criteria

The core is proved on three narrow programs before any widening, each against a strong baseline.

| Program | Baseline | Target | Kill if |
| --- | --- | --- | --- |
| DEFLATE and CRC-32 (compute) | the C version, clang -O2 | 0.9x of C or better | under 0.75x after the facts work |
| Campfire-class server (tables in SQLite, pages, live updates) | Burin today; the optimized Rust port | Burin's pages/s within 10%, memory within 1.2x | under 0.7x of Burin, or over 2x its memory |
| Game simulation (tables in memory, ticks) | Stasis ahead-of-time | equal speed; a small edit running again in 3 s | slower than 0.8x |
| Seeded slips (mutation harness) | crudspec's numbers | 99% of misspelled names caught at their line | under 95% |
| Refinements on the three programs | the same programs without them | at least half of bounds and overflow checks gone; no slower build than 1.2x | builds over 2x slower, or no checks removed |
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

- Recursion is opt-in: only functions marked `recursive` may call themselves, directly or through a cycle. A recursive cycle can't hold a growing value across its recursive call, and its depth is bounded on the native stack; going past the bound is a failure value, not a crash. Everything else stays recursion-free, so stack assignment stays simple.
- Two types for text and bytes: `Text` is always valid UTF-8, and `Bytes` is raw data (DEFLATE's output, files, the network). Going from `Bytes` to `Text` is a checked step that returns `Result`.
- Generics are copied per type (as Rust and C++ do): full speed, and LLVM sees concrete types, at a cost in code size and build time that the 3 s target has to absorb.
- Servers, games and tools weigh equally: the three-program validation stays as written.

**Open questions**

- Can development builds hold 3 s as programs grow, with per-module caching alone, or will they need a faster code generator for `-O0` (LLVM's FastISel, or splitting modules finer)?
- The language's name (the folder's is a working one).

**First steps**

1. Tables and typed ids: in-memory tables with generation-checked ids, one array per field.
2. Goose-style stack assignment for growing values, replacing the helper arena: `push`, text built from pieces, `out_byte` as a store and bump.
3. Refinements on parameters and fields (range, length, membership, index), inferred through the sign analysis and emitted as LLVM facts. Measured on DEFLATE.
4. `check fast == reference` and `test` blocks with `expect`.
5. Effects inferred on helpers, with the call path in errors.
6. The three-program validation above; then decide on widening.
