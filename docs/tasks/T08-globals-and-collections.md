# T08: globals, map, set, queue, ring and grid (milestone M2, part 3)

Depends on T07. Same rules. Read DESIGN.md "Where data lives", "Collections", "Who owns state", "Static allocation" and "Initialised before use".

## Globals

- `global app: App = App { ... }` at the top level: program state. In this task there's one worker thread, so a global's home worker is simply the program; `shared global` (snapshots and a writer) is later.
- **Static allocation:** the compiler sizes all globals; the runtime claims their memory in one piece at startup (reserved and committed: on Linux `mmap` with `MAP_NORESERVE` off, plus a check of `vm.overcommit_memory` and the cgroup limits as DESIGN.md "Static allocation" says, refusing to start with a clear message if the claim can't be guaranteed; a `--allow-overcommit` flag for development is fine if the report says so). After startup, globals never allocate.
- `prefault` touches every page at startup; `locked` (mlock) is optional in this task.
- **Initialisation:** defaults from struct definitions and the global's initialiser, evaluated at compile time when they depend only on constants (T05's evaluator; the starting state is data in the binary), otherwise once at startup before `main` (they may not read files or call effectful functions in this task). Every refinement is checked; a completed value failing an invariant fails startup.
- `inspect memory`: a `nlc inspect memory <package>` command printing each global's byte size and the total startup claim; a warning past a budget (64 MB default, set in the package manifest `package.toml` key `globals_budget`).
- Functions reading or writing a global: plain reads and writes (one thread). Passing a global as `write` follows T04's rules.

## More collections (all bounded; fixed-size elements only, as in T06)

- **`map<K, V, N>`** and **`set<K, N>`**: keys of integer, `bool`, payload-free enum, or struct/enum types built only from those (hashable by structure); a key type outside that is a build error (traits come later). Operations: `get(k) -> Option<V>`, `set(k, v) -> Result<(), Full>` (fails only for a new key in a full map), `remove(k) -> Option<V>`, `contains(k)`, `count()`; for sets `add`, `remove`, `contains`. Open addressing with a fixed table; iteration order is the order keys were first inserted (deterministic, as DESIGN.md wants for replays), not hash order. Views: no `set` of a new key or `remove` while iterating.
- **`queue<T, N>`**: `push` (`Result`), `pop` (`Option`), `peek`, `count`. **`ring<T, N>`**: `push` overwrites the oldest when full (never fails), iteration oldest to newest.
- **`grid<T, W, H>`**: a `W × H` fixed array indexed `g[x, y]` with `x: long 0..W`, `y: long 0..H` (proven indexes have no check), `g.width()`, `g.height()`; iteration in row order with `for c, x, y in g`.
- All are values that can be locals, fields and parts of globals; T06's and T07's rules on views, overlap, `discard`, proven pushes, the 64 KB local limit and printing apply.

## Acceptance cases

- Globals: compile-time-initialised state (no startup code in the IR for it); a startup-initialised global; a refined field with an invalid default (build error); `inspect memory` output and the budget warning; a global read and written from several functions; startup refusal when the claim can't be guaranteed (test with an artificially small limit through an environment variable the runtime reads only in tests).
- Map and set: insertion-order iteration after removals; a full map refusing a new key but accepting an update; struct keys; an unhashable key type (build error); a removal during iteration (build error).
- Queue and ring: FIFO order; a full queue's `Full`; a ring overwriting its oldest; empty `pop` and `peek`.
- Grid: proven and unproven indexes (the second fails with its line); row-order iteration.

## Report

docs/tasks/T08-report.md.
