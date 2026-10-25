# T23: touch only live collection elements (M3 follow-up, before T17)

Same rules (docs/PLAN.md). From docs/research/selfhost-architecture.md 2.3(b) and section 6 item 1, with the safety rules in docs/reviews/sol-selfhost-arch-r1.md points 2 to 4.

DESIGN.md says a large local collection is committed only as it's used (pages cost RAM when first written). Today the emitter breaks that: an empty `list<long, 6000000>` holding one element touches 48 MB, because empty literals, construction, copies and returns write or move the full capacity. This task makes the rule hold everywhere.

## The rule

No code path writes, reads, copies, compares, hashes or prints a collection past what its representation needs:

- **list, queue, ring:** an empty one writes only its header (count, and for queue/ring head and length). Copies, returns, equality, printing and hashing touch only the live elements (for a wrapped queue or ring, both live segments).
- **map and set:** lookup reads 8-byte bucket entries first (zero meaning empty, negative a tombstone), so the bucket array must be initialised to empty, not only the occupancy flags; insertion-order records, hashes and values are touched only as used. Either initialise buckets and flags in full (they're the per-slot metadata, much smaller than keys and values; state the bytes per slot) or redesign probing so untouched buckets are never read; say which and why. Copies keep or rebuild buckets, tombstones, hashes and insertion order exactly (iteration order must not change).
- **pool:** add a high-water mark (the end of the initialised slots). Slots at or above it are free with generation 1 and need no writes; the free list holds only slots below it. Lookup, iteration, equality and printing check the high-water mark before reading a slot's flag or generation, so a stale id into an untouched slot is reported as stale, never read from garbage. Removed-slot generations, retirement (a slot whose generation would overflow is never reused) and the free-slot order are kept through copies and resets.
- **Construction and copies:** struct and enum construction initialise collection fields by the rules above, not with a memset of the whole destination; copies and returns move only live parts; returning a local collection builds it in the caller's destination (as T14 does for Ascii), not a callee local plus a copy.
- **Whole-value loads and stores:** audit every place the emitter loads or stores a whole collection value (equality and printing load whole operands today), not just explicit memcpy/memset calls. Include nested collections (a struct of lists, a list of structs holding lists), enum payloads with collections, and fixed arrays and grids (which are always fully live: their rule stays full initialisation).
- **Runtime:** `fs.read` and `fs.list` in runtime/nl_runtime.c clear their whole destination on entry and on failure; make them set the count only (and clear only what they wrote, if anything).

## Acceptance

- Maximum RSS (measured with /usr/bin/time from a built binary) for: a local `list<long, 6000000>` holding one element (48 MB today; target under 2 MB above an empty program), the same as a struct field, a returned `list<long, 2000000>` (32 MB today), an empty `map<long, long, 1000000>` and `pool<T, 2000000>` holding one element each (state the metadata bytes they still touch and why).
- Determinism on dirtied pages: a test that fills a region with garbage (build and drop a large collection full of nonzero data), then builds a fresh collection in the same space and checks equality, printing, hashing (as map keys), iteration order, map tombstones after removal and reinsertion, and stale pool ids (removed, retired, and pointing past the high-water mark) all behave exactly as on fresh pages.
- The whole existing suite passes; IR checks that `list {}` emits no memset over the element lanes.
- `nlc inspect memory`/`inspect contracts` unchanged in meaning; report peak pages touched for the probes.
- Report: docs/tasks/T23-report.md.
