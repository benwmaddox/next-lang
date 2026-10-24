# Claude: T12 review (sorting and searching)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass, plus probes in ~/nlprobe:

- `sort_by` of 40 units by distance to a point in `ctx`: correct order, and equal distances keep their original order across merge boundaries (stable).
- `sort` of an `int[5]` with a duplicate; `binary_search` found (first of two duplicates), missing in the middle, below and above.

Fix round 1 (prompt-T12-fix1.md): comparators that printed or wrote a global were accepted. The comparator type `fn(C, T, T) -> bool` has no effects bound, so it must be pure; now any effect is a build error ("a sort comparator must be pure"), including through a function value declared with effects.

Notes for later:

- `int` has no `abs()` method yet; add it with T18's number work.
- No array literal (`[5, 3, 3]`); arrays start from `fill(x)`. Worth a small task before S1, which will want literal tables.
- The 100,000-element sort waits for T13's regions (it's in T13's acceptance cases).
