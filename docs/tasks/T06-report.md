# T06 report: fixed arrays and lists

## Built

The compiler now supports fixed arrays (`T[N]`) and bounded lists (`list<T, N>`) of fixed-size values, including nested collections. Arrays can be filled with one value evaluated once, or default-initialized when every element has a valid default. Lists start empty. Capacities accept constant integer expressions, allow zero, and reject negative, nonconstant, overflowing, or oversized values.

Arrays support indexing and constant `len()`. Lists support indexing, `count()`, `push`, `pop`, `insert`, `remove`, and `clear`. Indexes are `long`; unproven indexes emit a runtime bounds check that reports `index out of range`. The checker proves common array-loop indexes and elides their guards. `push` and `insert` return `Result<(), Full>`; `discard` accepts only those operations. Proven pushes keep their `Result` type while omitting the impossible full branch, with count facts joined across branches and bounded loops and invalidated by writes or calls that can change a list.

Collection `for` loops use the entry length as a snapshot. Writable element views update their collection, allow appending, and prevent structural changes, replacement of enclosing storage, and overlapping write calls until the loop ends. Break, continue, return, and `?` paths pass through the existing loop cleanup hooks. Place checking includes collection indexes, rejects uncertain overlaps, and permits proven-distinct indexes and fields, including forwarded write parameters. Receivers, indexes, and arguments are evaluated once in source order.

Collections print with brackets and compare by length and active elements. The constant evaluator supports collection construction and operations in cacheable functions. LLVM uses field lanes for collections of structs; nested lists remain inline in their enclosing field lane, with independent counts and their own item lanes. The IR fixture checks those types, array guard elision, and entry-block allocas for loop-body collections. Locals exceeding 64 KB are rejected with the M3 lowering diagnostic. No external crates were added.

## Build and test

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
cargo test
```

Both commands pass. `cargo test` reports 4 unit tests, 1 LLVM IR test, and 3 integration tests passing. The package integration tests check all 135 `tests/run/` directories and all 8 `tests/test/` directories, including 34 T06 runtime, bounds, and build-error fixtures plus the T06 collection-equality test.

## Choices for details left open

- Collection views are compile-time aliases with no runtime ownership record. The emitter snapshots a list count at loop entry and uses the loop counter to load or store the current element.
- A struct collection has one outer array per direct field. A nested collection field is stored as an array of inline collection values; each nested list value contains its own count and capacity lanes. This keeps nested counts independent without pointers.
- A proven unused push is accepted only when its count fact establishes success. Its expression remains `Result<(), Full>` when used with `match`, `?`, or `unwrap()`.
- Temporary local collection storage stays on the native stack in this milestone. The checker rejects any single local collection larger than 65,536 bytes and includes nested collection storage in its size calculation.

## Remaining work

T06 is complete. Pools and owner parameters remain in T07; globals remain in T08.
