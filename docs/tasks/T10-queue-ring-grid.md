# T10: queue, ring and grid (milestone M2, part 5)

Depends on T09. Same rules. Reviewed: docs/reviews/sol-T08-T09-r1.md (point 8).

- **`queue<T, N>`** (first in, first out): `queue {}` starts empty; `push(x) -> Result<(), Full>`; `pop() -> Option<T>` and `peek() -> Option<T>` (copies); `count()`. Under a live view, `push` is allowed (not visited, as in T06) and `pop` is a build error.
- **`ring<T, N>`**: `push(x)` returns nothing; when full it overwrites the oldest; a zero-capacity ring drops what's pushed. `pop`, `peek` as for a queue; iteration oldest to newest. Under a live view, a `push` that could overwrite (the ring might be full) is a build error.
- **`grid<T, W, H>`**: a `W × H` fixed array, needing element defaults or `fill(...)` (evaluated once); `g[x, y]` with `x: long` and `y: long` (proven in-range indexes carry no check; otherwise `index out of range` before any store, checked for each coordinate); `width()`, `height()`; `for c, x, y in g` in row order (`y` outer, `x` inner).
- T06's rules carry over: constant capacities (zero allowed), size-product overflow checks, the 64 KB local limit counting metadata, views and overlap, `discard`, proven pushes, printing (`queue[1, 2]`, `ring[...]` oldest first, grids as rows `[[1, 2], [3, 4]]`), structural equality.
- Acceptance cases: FIFO order; queue `Full` with contents unchanged; empty `pop`/`peek`; ring wraparound past capacity several times; a zero-capacity ring; grid proven and unproven indexes (each coordinate failing before a store); row-order iteration; a read-only grid write (build error); a queue pop under a view (build error); nested layout in IR; compile-time and run-time agreement.
- Report: docs/tasks/T10-report.md.
