# T23 report: touch only live collection elements

## Implementation

- Collection initialization and storage copies now recurse through structs, sums, fixed arrays and grids. Lists, queues and rings initialize only their headers and copy, compare and print live elements. Wrapped queues and rings copy both live segments while preserving their head and length.
- Maps and sets initialize their 8-byte bucket lanes and 1-byte occupancy lanes, for 9 bytes per slot. Hashes, keys and values remain lazy. Copies preserve buckets and insertion order and visit only active records below the entry end; ASCII key bytes are copied only up to their live length.
- Pools now carry a high-water mark in their 24-byte header. Operations avoid reading slot flags or generations at and beyond the mark, reuse freed slots before growing it, publish slots only after writing their value and metadata, and snapshot the mark for iteration. Pool copies, resets and returns remain refused. Equality compares live occupancy, generations and values, even when high-water marks differ.
- Storage-aware construction, assignment, call results, returns, T13 gather/scatter, equality, printing, and Option/Result payload paths avoid whole-value loads and stores for lazy collections. Safe large results use the caller destination; potentially overlapping calls use scratch storage and copy back after write arguments finish. Sort scratch initializes and copies only its live range.
- `fs.read` and `fs.list` set output counts to zero before work, publish counts after successful writes, and leave unused payload bytes alone. Byte-string construction also writes only the live bytes.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all run and test fixtures, parse snapshots, stack contracts, the no-element-lane-memset IR assertion, and the dirty stack-address reuse probe.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed. The wrapped queue/ring regression is a separate fixture so both T23 snapshots remain under the 100 KB limit.
- `nlc inspect memory` reports 9 bytes per map/set slot and still excludes local storage from startup claims. `nlc inspect contracts` continues to report reserved local/result storage, independently of which pages are touched.

The T23 fixtures cover small and large nested collection values, direct and indirect calls, caller-destination returns and aliases, `?` write copy-back, arrays and grids, Option/Result success and failure paths, map compaction and copies (including copied ASCII keys), pool reuse and stale IDs, sort sizes 15/16/17, and wrapped queue/ring copies at capacities 0, 1 and 3. Internal constant-evaluation tests seed retired, vacant and past-high-water pool states directly. The runtime IO fixture checks prefilled output buffers, failure counts, overflow, and sorted directory entries.

## RSS measurements

Each binary was built separately with `nlc build` and run in a fresh process using `/usr/bin/time -f 'max_rss_kb=%M elapsed_seconds=%e'`. `NLC_OPT_LEVEL` was unset, so the compiler used `-O1`. The platform was WSL2 Linux 6.6.87.2, x86_64, with 4,096-byte pages. Each binary reserved the default 64 MiB data stack; the reservation is virtual and pages are committed when written.

| Probe | Maximum RSS | Above empty | Estimated collection data-stack pages touched |
| --- | ---: | ---: | ---: |
| Empty program | 1,408 KiB | baseline | 0 |
| Local `list<long, 6000000>` with one item | 1,584 KiB | 176 KiB | 1 |
| `Holder` field `list<long, 6000000>` with one item | 1,584 KiB | 176 KiB | 1 |
| Returned `list<long, 2000000>` with one item | 1,584 KiB | 176 KiB | 1 |
| Empty `map<long, long, 1000000>` | 10,208 KiB | 8,800 KiB | 2,199 |
| `pool<Item, 2000000>` with one item | 1,584 KiB | 176 KiB | 3 |

The page estimates count collection storage writes, not all process pages; RSS also includes the executable, loader and runtime. A list's header and first element share one page. The map writes 1,000,000 flag bytes and 8,000,000 bucket bytes: about 245 flag pages plus 1,954 bucket pages. The pool writes its header, the first occupancy byte, the first generation (4 bytes), and the first element (8 bytes); the header and occupancy byte share a page, while the generation and value lanes use one page each. Its remaining free-list and element lanes stay untouched.

The local stack contracts remain capacity-sized even when RSS is low: the list probe reserves 48,000,008 bytes, and `make` reports a 16,000,008-byte caller result destination with zero callee-region requirement for its returned local. The task's “32 MB today” figure for a 2,000,000-element `list<long>` does not match this language's 8-byte `long`; the actual lane is 16,000,000 bytes, plus its 8-byte header.

## Binding interpretation

The broad acceptance text mentions hashing collections as map keys. The binding review correction keeps collections unhashable, so this implementation tests hashing only for supported scalar and ASCII keys. Pool copy/reset/return tests are likewise excluded because those operations remain intentionally refused.
