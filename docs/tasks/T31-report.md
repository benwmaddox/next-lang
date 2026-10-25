# T31 report: pointer-free collection text lanes

## Implementation

Growing `Ascii`, `Text`, and `Bytes` fields in collections now store no address. At maxima up to 64 bytes, the lane contains its length, Text code-point count where applicable, and inline bytes. Larger lanes contain a packed class-and-offset handle, length, and Text code-point count. The handle uses the high 8 bits for the class and low 56 bits for the byte offset from the collection base to the class slot, with `-1` as the empty sentinel. Allocation stores this offset; reads use it directly, and freeing derives the class slot index from the offset and class base. Class data lives in one flat byte region after the collection metadata, not in first-class per-class arrays.

Staging and publication order remains intact. A same-collection copy gathers the source, clears it to release its indexed slots, and then scatters the staged value, so a full-capacity copy can reuse freed slots. Map and set Ascii keys use pointer-free `{length, bytes[max]}` records and retain their per-entry copies. Static array, list, map, and pool constants initialize their class slots, handles, and high-water counters consistently with runtime values.

`inspect memory` reports each text lane's old and new metadata-plus-inline-payload size per element, capacity, and size classes. Examples from `tests/run/t16_collections`:

| Lane | Before | After |
| --- | ---: | ---: |
| `list<Row, 500>.name` (`Ascii max 60`) | 76 bytes | 68 bytes |
| `list<Text max 8 bytes max 32, 2>.element` | 56 bytes | 48 bytes |
| `list<Payload, 2>.note` (`Text max 300`) | 24 bytes | 24 bytes |
| `map<Ascii max 8, Payload, 2>.key` | 24 bytes | 16 bytes |

The small string lanes save 8 bytes per element by removing the pointer. Large text lanes keep the same descriptor-sized metadata; class storage and per-class free-list fields remain outside this per-element comparison. Map/set keys always retain inline key bytes because their current representation is a per-entry key copy.

## Acceptance coverage

- The new `tests/test/t31_collection_text_lanes` fixture copies a collection of structs with large Ascii, Text, and Bytes slots, mutates each copy independently, checks a global array and constant list/map with large text slots, and fills/frees/reuses 1,024 128-byte slots. The latter dirties 128 KiB of slot storage (32 4 KiB pages) before reuse.
- `compiler/tests/collections_ir.rs` checks collection declarations for pointer fields and rejects pointer stores to GEPs into collection string/key lanes. `compiler/tests/globals.rs` checks the reported before/after sizes.
- Existing T16, T14, and T23 fixtures were left unchanged and pass with the full fixture suite. The self-host integration test compares lexer and parser status, stdout, and stderr byte-for-byte against the Rust reference and passes.
- An initial single-slot stress fixture used an 8 MB value with many size classes; installed Clang 18 crashed in backend code generation. I replaced that probe with 1,024 slots in one 128-byte class. It still dirties multiple pages and verifies that freed class slots are reused.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all run/test fixtures, parse snapshots, self-host comparison, IR checks, stack tests, and doc-tests.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed; only the new T31 test snapshot was added.
- `git diff --check` — passed.
- Before/after native `bench/t30_locals` output is identical: `50000105000000` then `odd`.
- `scripts/bench-selfhost.sh` passed after the change with a 0.26 s best and 58,784 KiB RSS. The clean HEAD snapshot used for the before measurement gave 0.23 s and 58,784 KiB.

## Interleaved timing

I built clean HEAD from a `/tmp` source archive and the current source separately, then ran five alternating pairs against the same 13-file corpus (54,145 lines, 1,152,008 bytes). Values below are each side's best of five; RSS is maximum RSS for the best run.

| Workload | Before | After |
| --- | ---: | ---: |
| `bench/t30_locals` | 0.09 s / 1,584 KiB | 0.09 s / 1,584 KiB |
| Self-host lexer | 0.07 s / 14,080 KiB | 0.09 s / 14,080 KiB |
| Self-host parser with tokens and tree | 0.23 s / 58,784 KiB | 0.28 s / 58,784 KiB |

The parser best from the standalone `bench-selfhost.sh` runs was 0.23 s before and 0.26 s after. Timing varied between the paired and standalone runs; RSS stayed the same. The native bench program and self-host comparison output remained byte-identical.

## Data-stack addresses remaining for X1

T31 removes T16's stored collection string pointers and pointer-range slot checks. Collection lanes now retain indexes and lengths; Ascii map/set keys retain lengths and bytes. The remaining pointer paths from T29 still apply:

- Transient string descriptors point into locals, fields, builders, call results, collection element bytes, and `.bytes()` views while a read, comparison, print, or IO operation consumes them. Collection descriptors are formed at the use site from the collection base/index or class/slot.
- The generated calling convention uses pointers for write/grow parameters, large by-reference arguments, caller result destinations, gathered collection elements, and temporary copy-back regions.
- Generated GEPs and runtime destinations point at local regions, collection lanes, loop elements, and stack-backed IO buffers. These are live references, not addresses stored in collection text data.
- Literal descriptors may point at static string data. Those addresses do not point into the job's data stack.

## Fix round 1

### Selfhost slowdown

The profile placed the extra work in `load_and_lex` and `load_and_parse`, which read growing file-name fields such as `SourceFile.name` and `DirEntry.name`. The first handle format stored a class and slot index. Each read decoded that index, loaded class offsets and sizes, and multiplied by the class size. Handles now store the class and the byte offset from the collection base to the allocated slot. Reads use that offset directly; freeing derives the slot index from the known class base. Class selection and reuse still use the size table.

Five alternating runs over the same 13-file corpus (54,145 lines, 1,152,008 bytes) now agree with clean HEAD within timing noise: the parser bests match, and the lexer differs by 0.01 s.

| Workload | Clean HEAD | Fix round 1 |
| --- | ---: | ---: |
| Selfhost lexer | 0.10 s / 14,080 KiB | 0.09 s / 14,080 KiB |
| Selfhost parser with tokens and tree | 0.26 s / 58,784 KiB | 0.26 s / 58,784 KiB |

### Clang memory use

Per-class slot arrays are no longer fields of the named collection type. The type keeps collection lanes and free-list metadata; class data is laid out contiguously in a flat byte region. Allocation stores byte offsets in handles, and access uses `i8` GEPs. Large sum predicates read only the tag, and equality walks large storage without loading or storing the full aggregate. Standalone growing-string descriptors keep their pointer-and-length equality path.

`compiler/tests/collections_ir.rs` checks that the 8 MB collection type stays a small metadata prefix, its class backing is a flat byte array, and neither the prefix nor flat backing is loaded or stored as a whole. Its global backing region is 16,777,088 bytes. The 8 MB fixture uses `list<Ascii max 8_388_608, 1>` with all 17 size classes, alongside the 1,024-slot reuse test. Direct Clang compilation of the generated IR under an 8,000,000 KiB virtual-memory limit took 0.02 s and peaked at 80,256 KiB RSS. The capped end-to-end `nlc test tests/test/t31_large_classes_build` run passed in 0.53 s at 104,724 KiB maximum RSS. The full live-value probe required a 58.7 MB data-stack reservation and failed at runtime, so the stress fixture exercises the large backing during compilation while the 1,024-slot fixture covers allocation, mutation, free, and reuse at runtime.

A compile-time check rejects class-backed collection storage that cannot fit in the handle's 56-bit byte-offset field. The T15 append regression found during full-suite validation was fixed by keeping raw growing-string descriptors on their descriptor comparison path. Short string literals up to 64 bytes use direct byte stores; longer literals use a bulk copy.



### Verification

- `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target cargo test` — passed under the 8,000,000 KiB memory cap. This includes the selfhost lexer/parser comparison and both T31 fixtures.
- `scripts/update-parse-dumps.sh --update` — passed; both T31 test packages have frozen parse snapshots.
- `scripts/bench-selfhost.sh` — passed; best of five was 0.26 s and 58,784 KiB RSS.
- Five paired before/after parser and lexer runs had matching parser time and lexer times within 0.01 s.
- Direct capped Clang and end-to-end T31 stress fixture measurements are listed above.
- `git diff --check` — passed.

Temporary profiling corpora, the IR-dump helper, the clean-HEAD source archive, and the extra profiling targets were removed after verification.
