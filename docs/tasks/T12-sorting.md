# T12: sorting and searching (milestone M2, part 7)

Depends on T11. Same rules. Reviewed: docs/reviews/sol-T08-T09-r1.md (points 10 to 12).

General type generics and traits aren't designed yet (an open question for Ben), so sorting is a **compiler built-in** specialised per element type, not a library function using user-visible generics.

- `sort_by(xs, ctx, less)` for `list<T, N>` and `T[N]` in `write` mode, with `less: fn(C, T, T) -> bool` and `ctx: C` (read-only, and the checker refuses a `ctx` or `less` whose access overlaps `xs`, including through globals). `sort(xs)` for integers, `bool` and payload-free enums in their natural order.
- **Stable** (equal elements keep their order). Insertion sort below 16 elements; **iterative** bottom-up merge sort otherwise (T01 forbids recursion). The scratch buffer has the same bounded type as the input and counts toward T06's 64 KB limit, also when the input is a global (an oversized specialisation is a build error until M3). `less` must be a strict weak ordering (the doc says so; a debug build can check `less(a, a) == false` and fail if not).
- `binary_search(xs, key) -> Option<long>` on a list or array of integers, which must be sorted (stated, not checked, in release; a debug build checks): with duplicates it returns the first matching index.
- A limit on specialisations (each distinct element type and capacity is one), say 1,000, with a build error past it.
- Acceptance cases: sorting units by distance to a point given in `ctx`; stability across merge boundaries (more than 16 equal keys); already-sorted, reverse-sorted, empty, one-element and full inputs; arrays; every natural-order type; an overlapping `ctx` (build error); the scratch-limit refusal; `binary_search` found, missing below, missing above, empty, and duplicates returning the first.
- Report: docs/tasks/T12-report.md.
