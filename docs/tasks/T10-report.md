# T10 implementation report

Implemented bounded queues, rings and grids across parsing, type checking, constant evaluation, and native LLVM emission.

## Delivered

- Added `queue<T, N>`, `ring<T, N>`, and `grid<T, W, H>` types with constructors, defaults/fill, methods, indexing, iteration, printing and structural equality.
- Queues preserve FIFO order and report `Full` without changing contents. Rings overwrite the oldest value when full, drop pushes at capacity zero, and expose FIFO order across wraparound. Both support copying `pop` and `peek` results.
- Grids use row-major storage and iteration. Grid indexing checks x and y independently before a store, with proven coordinates avoiding runtime checks; `width()` and `height()` return refined counts.
- Carried over collection capacity/product overflow checks, metadata-inclusive 64 KB local limits, view and overlap checks, and nested structure-of-arrays layout. Added run fixtures for the requested success cases and diagnostics, plus IR layout coverage.

## Decisions

- Ring pushes under a live view are accepted only when bounded iteration proves the push cannot overwrite a viewed element; otherwise they are rejected.
- Grid dimensions are individually constrained to the supported `long` range as well as checking their product for overflow.
- T10 fixtures exposed an emitter assertion that rejected refined numeric payloads with the same LLVM representation as their base type. The assertion now checks representation compatibility, preserving T06's refined-long behavior.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `cargo test` — passed: 6 unit tests, 2 collection IR tests, 3 globals tests, 3 language integration tests (including all run and test fixtures), 1 pool IR test, and doc tests.
- No external crates were added. No commits or branch changes were made.
