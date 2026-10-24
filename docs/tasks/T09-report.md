# T09 implementation report

Implemented bounded maps and sets across parsing, type checking, constant evaluation, and native LLVM emission.

## Delivered

- Added `map<K, V, N>` and `set<K, N>` types with empty `map {}` and `set {}` constructors, the requested operations, bounded open addressing, tombstones, and compaction on insertion when entry storage is exhausted.
- Preserved insertion order through updates, removals, compaction, printing, and iteration. Added structural equality that compares membership and map values independently of insertion order.
- Added recursive logical-field hashing for supported keys, including structs, enums, and owner-typed IDs. Compile-time constants use the same hash/index rules as runtime maps and sets.
- Added hashability, pool containment, owner lifetime, mutability, result-handling, and live-view checks. Map keys and set keys are immutable in iteration; map value fields remain writable.
- Added run fixtures for collisions, full tables, tombstones, compaction, update/removal order, constant/runtime agreement, struct and ID keys, printing, equality, writable map values, and required compile errors.

## Decisions

- Map and set literals start empty, as specified; entries are added with `set` and `add`.
- A `set` or `remove` operation on a map with an overlapping live view is rejected conservatively because the checker cannot prove that the key is unrelated to the viewed entry. Helper calls that can mutate a nested map or replace a viewed map value are also rejected.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `cargo test` — passed: 6 unit tests, 1 collection IR test, 3 globals tests, 3 language integration tests, 1 pool IR test, and doc tests.
- No external crates were added. No commits or branch changes were made.
