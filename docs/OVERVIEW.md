# next-lang in brief

A short, shareable description of the language as designed on 2026-10-26. The full design is [DESIGN.md](DESIGN.md); the roadmap is [PLAN.md](PLAN.md). Syntax is still a proposal and may change in details.

## What it is

A general-purpose compiled language for servers, games and command-line tools. It compiles through LLVM to native code and has **no garbage collector and no borrow checker**. Its bet is that most of what goes wrong in programs can be a build error, if the language knows how big every value can get and who may change it.

- **Correct first:** no null (`Option` and `Result` instead), integer overflow is always checked, every collection has a capacity, every text a maximum length, and a function can change only what it's given.
- **Easy to read and write,** for people and for AI: one way to declare a function, no name shadowing, no mutable globals, no macros, a small fixed set of attributes.
- **Efficient by construction:** data laid out for the CPU cache, memory reclaimed by resetting a stack pointer, and threads that share nothing mutable, so the common operations need no locks.

```
struct Unit {
    name: Ascii max 32
    hp: int 0..=1000                       // a range: checked on every write, stored in 16 bits
    inventory: list<Item, 8>               // at most 8 items, stored inside the unit
}

fn heal(units: write list<Unit, 4096>, amount: int) {
    for u in units {                       // u is a writable view of each element
        u.hp = min(u.hp + amount, 1000)
    }
}

fn describe(u: Unit) -> Ascii max 64 {
    $"{u.name}: {u.hp} hp"                 // interpolation; the result's maximum length is computed
}
```

## Values and types

- **Structs, enums with data, `Option`, `Result`, `match`** (exhaustive), `?` to pass an error up, `??` for a fallback.
- **Ranges as types:** `int 0..=100`, `long`, `byte`. A value outside its range can't be stored; the compiler uses ranges to pick storage width and to remove checks it can prove unnecessary.
- **Three text types:** `Text` (always valid UTF-8, validated once at the boundary, so nothing re-checks it), `Ascii` (one byte per character, the compact form) and `Bytes` (raw data). Each stored text has a maximum: `Text max 80`.
- **Interpolated strings** `$"{a} and {b}"` cost the same as hand-written concatenation: the size is known at build time and the text is written straight into its destination.
- **Effects and capabilities:** what a function may touch (database, files, network, clock, randomness, output) is part of its type, inferred across calls, and granted only by the entry point as values (`Db`, `Fs`, `Clock`). A library can't reach the network unless someone hands it a capability, and tests and replays can supply fixed clocks and random sources.

## Memory: bounded values, stacks, bump allocation

This is the core of the design. The idea being tested: a stack-and-arena model gives better **locality, less bookkeeping, more compact data and trivially cheap cleanup** than per-object heap allocation, without Rust-style ownership rules.

**Every value has a known maximum size.** Collections (`T[N]`, `list`, `pool`, `map`, `set`, `queue`, `ring`, `grid`) carry their capacity in their type, and texts their maximum length. So a collection is an ordinary value: it can be a local, a field, a parameter or a result, stored inline, with no pointer to chase.

**Data is laid out by field, not by object.** A `list<Unit, 4096>` stores all the `hp` values together, all the names together, and so on (structure of arrays). A loop that touches only `hp` streams through only `hp`, and LLVM can vectorise it. Ranges shrink storage further (`int 0..=1000` takes 16 bits).

**Each job has its own data stack, and allocation is a pointer bump.**
- A local value, a function's result, a text being built: each takes the next bytes on the job's data stack. Allocating is adding to a pointer and comparing it with the end; there's no `malloc`, no free list and no lock.
- Freeing is resetting the pointer when a scope ends (a block, a loop iteration, a function, a whole request). A request that built a thousand temporary values frees them all in one step.
- Results are built in place: a function returning a text writes it straight into space its caller reserved; `out += piece` appends straight into the builder. No intermediate copies.
- References into the stack are **offsets**, not addresses. That lets the stack **start small and grow by moving** to a larger mapping when it needs to (the operating system's `mremap`), with nothing to fix up. Pages are committed only as they're touched. The starting size comes from a typical-run estimate the compiler computes (every loop assumed to run at most 5 times), at least one page.
- Stacks are pooled per worker thread and trimmed by recent demand, so a busy server reuses warm memory and an idle one gives it back.
- When a loop really needs an open-ended collection, it can opt in: `list<Entry, unbounded>` grows at the stack's tail, contiguous, never copied. It's only allowed for locals that grow at the top of the stack, never in shared state or fields.

**Parameters say what a function may do with its arguments,** and the compiler checks the call sites:
- read (the default): passed by reference, never copied, can't be changed;
- `write`: may change it in place, even an `int`;
- `grow`: may append to a text or collection;
- `take`: moves ownership.

The compiler proves that arguments a function can change don't overlap with anything else it receives, so there's no aliasing to reason about, and it can tell LLVM so.

**No C library in the standard library.** The core library is written in next-lang directly over operating-system calls; its programs are freestanding static binaries (a trivial program is about 15 KB). External C libraries can still be called through typed bindings that declare their effects.

## How a program is divided into jobs

A **job** owns its stacks: its own data stack and native call stack, isolated from every other job's. A new job starts only where work may run at the same time as its caller, or outlive it; everything else is an ordinary call.

| Piece | Its stacks |
| --- | --- |
| `main`: creates program state, shared state and capabilities | its own, for the whole run |
| a request handler (`@[page]`, `@[action]`, `@[api]`) | its own, one per request, reset afterwards |
| a spawned job (`@[job]` functions only) | its own |
| a service: a long-lived job that owns its state and reads a mailbox | its own, for its lifetime |
| a chunk of a parallel loop | its own scratch, freed at the join |
| an ordinary function call | the caller's |

- **Program state** is a local in `main`, passed down as `write app: App`. There are no mutable globals: a function changes only what it's given, visible at every call.
- **A game** runs inside main's job: the host calls `tick(game: write Game, input: Input)` and `draw(game: Game, frame: write Frame)` each frame, as ordinary calls, so a frame costs no job start or copy. `draw` takes the state read-only, so it can't change it.
- **A server's** `main` opens the database, creates its shared values and calls `serve`; each request is a job with its own bounded memory.

**Threads:** one worker thread per core, pinned. Each worker runs jobs. A job that waits for I/O is **suspended without `async`/`await`**: the code reads straight down, the job keeps its own stacks, and the worker runs other jobs until the I/O completes (as Go's goroutines do). A job stays on its worker, so its stacks are only ever touched by one thread.

## Crossing threads

**Nothing mutable is shared between threads.** Values cross in four ways only:

1. **Mailboxes (queues of flat values).** A flat value is one contiguous block with no pointers in it (data inline, typed ids instead of pointers), so sending it is one copy into the queue and one onto the receiver's stack. Queues are bounded rings: one producer and one consumer where possible, with no locks; many producers to one consumer where needed. A **service** job owns its mutable state as ordinary locals and is reached only through its mailbox; a cache, a log writer or a game's audio mixer is written this way. Starting a service is an explicit act, and it receives only copies, capabilities, shared handles and queue ends.
2. **Snapshots of shared state.** For data many jobs read while it keeps changing (presence, counters, a live game world), a `shared` value is created in `main` and passed to the jobs that need it as a parameter (`online: shared Presence`). It has **one writer**. Readers see an immutable snapshot, pinned once per read phase and never per element, and never across a wait, so a slow reader can't hold old versions forever. Changes go to the writer as batches; a `transaction { }` block runs on the writer against its latest version, all or nothing, so check-then-act races can't happen.
3. **Frozen pools.** Big structures built once and then read by many threads (a compiler's syntax trees, a game level, a search index): each builder is owned by one job, then `freeze` turns it into read-only memory with no copy. Builders can be filled in parallel, one per file, and grouped into a batch whose ids can't be mixed with another batch's.
4. **Parallel loop inputs and results** (below).

A typed id names an element of a pool (an index plus a generation), not a memory address, so it means the same thing on every thread reading the same snapshot.

## Parallel processing

```
let lengths = parallel for t in texts { t.len() } collect
let total = parallel for i in 0..n { cost(i) } reduce sum
```

- **Work stealing:** the runtime splits the loop into chunks that idle workers take from busy ones' queues; small loops run sequentially below a cost threshold, so a fork never costs more than it saves.
- **Structured:** the caller waits for every chunk, so its stacks stay alive and unchanged. Chunks read the caller's data through read-only views, **with no copying**, and may read its pinned snapshot.
- **No data races by construction:** a loop body may have no effects and may write only its own scratch and its own slot of the result.
- **Deterministic results:** `collect` writes results in index order; `reduce` combines chunk results in a fixed tree order whatever the scheduling, so even floating-point sums are identical on every run.
- **No nesting in v1:** a parallel loop inside another runs sequentially, so workers can't all end up waiting for work nobody can run.

**Open questions** (decided direction, details still open): whether `spawn` is allowed only inside a `scope { }` that joins its children, cancels siblings on failure and passes deadlines down (structured concurrency, the current direction); whether calls that may suspend get a `wait` keyword or only an editor marker; and how to make very wide fan-out (thousands of concurrent I/O tasks) cheap. Stackless `async`/`await` was considered and set aside: it brings function colouring, two kinds of function values and cancellation at every `await`.

## Where it stands (2026-10-26)

- A first compiler in Rust (now frozen as "stage 0") compiles most of the language today. A **self-hosted compiler**, written in next-lang itself, is the primary line of work: it already builds structs, enums and `match`, produces identical results to stage 0 on every test it supports, and is gaining collections, the moving data stack, text and builders next. The goal is for it to compile itself.
- Early benchmarks against equivalent Rust programs (both at their highest optimisation, same CPU target): on **allocation-heavy work next-lang is already faster** than idiomatic Rust (2.6x on text formatting, 1.5x on nested lists, 5 to 8% on per-request scratch work) and level with hand-tuned buffer-reusing Rust; peak memory is equal or lower, and binaries are a third the size (a fifth with the self-hosted compiler). On **tight arithmetic loops it's 1.1x to 5x slower** (10x on binary search), mostly from always-on overflow and bounds checks blocking vectorisation; removing the checks the compiler can prove unnecessary is the next performance step.
