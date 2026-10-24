# T12 implementation report: sorting and searching

## Delivered

- Added compiler built-ins `sort(xs)`, `sort_by(xs, ctx, less)`, and `binary_search(xs, key)` for bounded lists and fixed arrays. Natural sorting supports integers, `bool`, and payload-free enums; `sort_by` accepts a read-only context and comparator over any supported element type.
- Sorting is stable: inputs shorter than 16 elements use insertion sort, and longer inputs use iterative bottom-up merge sort. Scratch uses the same bounded collection type as the input and is reused by type within a function.
- `sort_by` records comparator calls in the existing indirect-call and global-effect analyses. The checker rejects direct context overlap, context/comparator expression access to the sorted global, comparator access to the sorted global, and sorting a viewed collection, including through a helper.
- `binary_search` uses a lower-bound search and returns the first duplicate index as `Option<long>`. Debug builds check that the input is sorted and fail at the call site if it is not; release builds trust the caller.
- Added a 1,000-specialization limit, keyed by element type and capacity. Scratch is checked against the temporary 64 KB native-stack bound, including input-plus-scratch for a local input, all scratch types used in one function, and global inputs.
- Added language fixtures for context-based unit ordering, stability across merge boundaries, natural ordering of each supported type, boundary and duplicate binary searches, unsorted debug input, specialization and scratch limits, and overlap errors.

## Decisions and remaining contract

- Sorting is rejected during constant or global initialization; call it from a function.
- A comparator must implement a strict weak ordering. The compiler cannot prove that property, so it remains the caller's responsibility; no `less(x, x)` debug check was added.
- `binary_search` requires sorted input. Debug builds check it; release builds do not.
- The specialization cap also covers `binary_search` specializations because it uses the same compiler-specialization path.
- No task requirement was impossible or contradictory. No external crates were added.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all T12 language fixtures.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check` — passed.
- Run the T12 language tests with `nlc test tests/test/t12_sorting`.

## Fix round 1

- Changed the `sort_by` comparator contract to the pure type `fn(C, T, T) -> bool`. Named comparators are checked using T11's inferred-effect validation; function values with an effects bound are rejected by the normal function-type assignment rule. Diagnostics name the extra effect and say a sort comparator must be pure.
- Removed comparator global-access overlap checks that are redundant under the pure contract. The direct context/collection overlap check and the hidden global-access context/collection check remain.
- Added refusal fixtures for a printing comparator, a global-writing comparator, a global-reading comparator, and a function value declared with an effects bound. Added an acceptance test for a pure comparator passed through a function value. Updated the previous global-overlap fixture to expect the purity error.
- Verification: `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build`, `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test`, and `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` all passed.
