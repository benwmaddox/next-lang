# Text arena: unbounded text as windows into an arena

Status: design note with open proposals, 2026-11-03. Stage 1 is implemented as a library written in next-lang itself
(`tests/c_runtime/text_arena/text_arena.nl`, no compiler change); the built-in spelling below is the target. Backlog item 4.

## Why

`Bytes max N` is inline at its maximum (DESIGN.md, "Stored values are inline at every bound"): every value reserves N bytes and is
copied by value. go2nl converts Go `string` to `Bytes max N` with one N for a 1-16 MiB source file, so every string reserves that much,
frames are huge and scanner time is quadratic (407 KB: 206 ms vs Go 3.8 ms; 1.63 MB: 5.1 s). A string longer than N fails. Text should
not need a maximum.

## What is decided, and what is only proposed

**Decided** (BACKLOG item 4): a growable text arena exists as a concept: text without a per-value maximum, whose bytes live in an arena of
declared capacity, so a value is small plain data and many values coexist with large ones.

**Everything below marked PROPOSAL is open for the maintainer.** Stage 1 is a deliberately minimal, provisional library built only to
test the core idea (arena, window, slice without copy, content equality, copy-out); names and shapes are easy to change.

### The core idea (what stage 1 tests)

- An **arena** is a byte region of declared capacity N, owned by its declaring local, parameter or struct field, never copied. Stage 1
  uses `pool<byte, N>` because pools already give the capacity, pass-by-address and owner machinery.
- A **window** is plain data (start, length; one long in stage 1): copied freely, never owning bytes. A window of arena A cannot be used
  with arena B: stage 1 reuses the pool-owner check (`expected b.Id, got a.Id`), spelled `Id<src>`.
- `slice` makes a smaller window without copying; equality and order are by content; copy-out to a bounded value is checked.

### PROPOSALS (open)

1. **Surface type.** (a) A separate type without a maximum, e.g. `Text<src>` / `Bytes<src>` (leading proposal: a missing `max` means
   unbounded, and the angle bracket names the arena). (b) An option on the existing types, e.g. `Text max *` or `Text in src`. (c) A new
   name such as `Window<src>` or `View<src>` (BACKLOG's explicit-environment note proposes a `View` family). Tradeoff: (a) reads
   naturally but makes `Text` and `Text<src>` look like one type while behaving differently (immutable, arena-bound); (c) is honest
   but adds a name.
2. **Which arena.** (a) The window names its arena as an owner, like pool ids; every creating operation takes the arena (`src.add(s)`).
   Explicit, matches the explicit-environment principle, costs a parameter. (b) An implicit per-job arena: no parameter, windows are
   not tied to an arena by the type, but it is exactly the ambient state the principle rejects and breaks when two arenas (source,
   generated text) are wanted.
3. **Mutability.** (a) Windows immutable; bounded `Text max N` stays mutable (in-place append/replace). Zero-copy `slice` is then sound:
   substrings alias safely with no write-through hazard. (b) Windows mutable in place: slices would alias writable bytes, so `slice` would
   have to copy or the language needs a rule for who may write. (c) Windows immutable plus an explicit `Text max N` buffer to edit and
   `add` to freeze it. (a) or (c) is recommended.
4. **Small values inline.** Option B in the table below (inline when short, spill to the arena): two shapes, every operation branches.
   Leave out until measurement shows most windows are tiny.
5. **Construction.** Appending to the arena's end through a builder (one open per arena, or builders with their own region) is the
   natural way to make generated text; whether it is a builder object, a `write` parameter, or just `add` of bounded pieces is open.
   Stage 1 has only the minimum needed to fill a large arena in the test.
6. **Conversions.** bounded -> unbounded is a copy into the arena; unbounded -> bounded is a checked copy-out that fails when too long.
   Comparison, ordering and hashing by content across both kinds. Windows as pool/struct fields and map keys (content hash) are plain
   data under the owner rule. All proposed; only copy-out and equality are in stage 1.

### Questions for the maintainer, in plain words

1. Should unbounded text be a separate type, or an option on `Text`? What should it be called?
2. Must a text value always say which arena it belongs to, or may a job have one implicit arena?
3. Is unbounded text read-only once made? (Needed for cheap, safe substrings; editing then means making a new text.)
4. Is it acceptable that replacing an unbounded text field wastes the old bytes until the whole arena is reset? Or should such state keep
   `Text max N`?
5. Are small strings worth a special inline form, or is one 8-16 byte window for everything enough?
6. Where does a compiler's generated text (unescaped strings, messages) live: the same arena as the source, or a second one?
7. Should the arena size limits (2 GiB, start/length packing) matter, or is a larger window (16 bytes) wanted from the start?

## Why this is not a heap

One region of declared capacity, reserved up front (address space reserved, committed lazily by the OS, so a large declared capacity such
as 256 MiB is not a memory bill: untouched pages cost nothing). Bump allocation only. No per-value free, no compaction, no size classes,
no headers, no reference counts. Freed or reset only in bulk (per-job or per-run arena reset, DESIGN.md "Per-run locals and arenas"),
and a window cannot outlive a reset: the owner check ties it to its arena like a pool id. Exhaustion is visible: the program fails
("unwrap called on none" today). The allocation is the declaration; nothing is allocated later.

## Options compared

| | A: inline at the max (today) | B: small inline + spill to arena | C: uniform windows |
|---|---|---|---|
| Value size | N bytes each | 24+ bytes, two shapes | 8 (stage 1) to 16 bytes |
| Copy cost | N | branches | constant |
| Unbounded length | no | yes | yes |
| Complexity | none | spill needs the arena anyway; every operation branches | one representation |

Recommend **C for large or unbounded text** (source files, file contents, derived substrings) and **A for small bounded fields**. B
would pay only if measurements show most windows are tiny and 8-16 bytes per window hurts; it is left out of stage 1.

## Two kinds of text in a compiler

1. Substrings of an immutable input: zero-copy windows into the source region (`slice`).
2. Generated text (escape-processed token values, canonical numbers, messages): appended through a builder to a generated-text region
   of the same arena or a second arena. Both are append-only until reset.

## Operations (provisional names; the built-in column is a proposal)

All take the arena first. Exhaustion, a bad slice and a bad index fail the program.

| Operation | Stage 1 library | Built-in target |
|---|---|---|
| create from literal / bounded value | `arena_add_ascii(src, s)` | `src.add(s)` |
| length | `arena_len(src, w)` | `w.len()` |
| slice, no copy | `arena_slice(src, w, a, b)` | `w.slice(a..b)` |
| byte at | `arena_at(src, w, i)` | `src[w][i]` |
| equal / order by content (hash: not in stage 1) | `arena_equal`, `arena_less`, | `==`, `<`, map key hash |
| starts_with, find, hash | not in stage 1 (easy on top of `arena_at`) | methods, map key hash |
| checked copy-out to bounded | `arena_to_bytes_256` | `w.to_bytes()` (N from the expected type) |
| print | `arena_print(env, src, w)` | `print(w)`, interpolation |
| builder | `m = arena_begin(src)`, `arena_push`, `arena_append_ascii`, `arena_finish(src, m)` | `src.begin()` .. `.finish()` |

Departure from the first sketch: `w[i]` needs the bytes, and a window carries no address (DESIGN.md: stored data holds no addresses; a
window is (start, length) plus a *static* owner), so byte reads name the arena. A built-in `==` between windows of the same owner would
read the arena known from the type.

Conversions: bounded -> unbounded is a copy into the arena (`add`). Unbounded -> bounded is a checked copy-out that fails when too long.
Comparison, ordering and hashing are by content across both kinds (the built-in compares a window with an inline value without
copying). A window may be a struct field, a pool or list element, or a map key (hash by content): plain data under the owner rule. Stage 1
is not done: map keys by content need a compiler hook and are not done.

## Builder (PROPOSAL; stage 1 has only begin/push/finish)

A builder writes at the arena's end, so **one builder is open per arena**: `begin` returns the start mark and `finish(mark)` the window of
everything appended since. Other appends in between would interleave, and the built-in `begin` should hold the arena's write access until
`finish`. Builders with their own region (a second arena for generated text) allow several at once.

## Immutability and zero-copy slices (follows from proposal 3a)

Because a window's bytes never change, any number of windows alias the same bytes safely: a substring is a smaller (start, length), with
no write-through hazard and no copy. The arena only grows, so windows never dangle before a reset. The library never overwrites arena
bytes (`pool.set` is not used).

## Limitation

The arena is append-only: replacing an unbounded text field allocates new bytes and the old ones stay until the arena is reset. Unbounded
text suits per-run/per-job data and immutable inputs. Long-lived mutable state that edits text repeatedly should keep `Text max N`.
Stage 1 limits: start and length are packed in one long (arena up to 2 GiB); the library window type `Id<src>` is the same type as the
arena's own byte slot ids (the built-in `Text<src>` would be distinct); the helper `arena_slot` is the one place that builds an id by arithmetic.

## Go port mapping (stage 3 sketch, assumes the proposals above)

- Go `string` -> unbounded window `Text<src>`; `s[a:b]` -> `slice`; `len(s)` -> `len`; `s[i]` -> byte read; `==`, `<` -> content compare.
- `strings.*` shims (`HasPrefix`, `Index`, `Contains`, `TrimPrefix`) -> `starts_with`, `find`, `slice` over windows.
- Go `[]byte` -> `Bytes max N` or `list<byte, N>` (mutable, bounded). `[]byte(s)` -> checked copy-out. `string(b)` -> `add` (copy into the arena).
- `strings.Builder` -> arena builder.
- The scanner's `text` field is a window into one source arena (loaded once, immutable); token values are windows into it, or into a
  generated-text arena when escape processing changes the bytes.

## Stage 1 status

Done: provisional library (add, len, slice, at, equal, less, copy-out to 256 bytes, print, minimal builder); test `tests/c_runtime/text_arena` (5 MB arena, 3 million slices, a
read-only 5 MB arena through 2000 recursive calls, which would overflow the stack if copied) and negative test
`tests/pool_owner_errors/text_arena_wrong_arena`. Remaining: the built-in `Text<src>` / `Bytes<src>` types and sugar, content-hash map keys,
interpolation, arena reset, UTF-8 validation for `Text<src>`, a distinct window type.

## Decisions (maintainer, 2026-11-04)

1. Unbounded text is a **separate type** (not an option on `Text`). Name still to choose.
2. A text value **always names its arena** (owner-checked like pool ids); no implicit per-job arena.
3. Unbounded text is **read-only once made**; editing means making a new text. This is what makes zero-copy substrings safe.
5. **One window representation** for all unbounded text; no special small-string inline form.
6. Generated text lives in the **same arena** as the source (append-only region of it).
7. A **32-bit start and 32-bit length** window is fine (Go's own positions are 32-bit); about 2 GiB per arena.

All seven questions are decided (question 4 below).

4. **Decided (2026-11-04): accept the waste and rely on bulk resets, keep `Text max N` for long-lived edited state.** Replacing an unbounded text leaves its old bytes until the arena is reset; arenas are per run, per job or per file version and are dropped whole. An arena reports how much it has used, and exhausting the declared capacity fails loudly, so a program that keeps replacing unbounded text in a long-lived field is caught, not silent. No free lists, no compaction (that would be a heap or a garbage collector). Rule for programmers: long-lived state whose text is edited in place uses `Text max N`; unbounded text is for per-run data and immutable inputs.

8. **Decided (2026-11-04): arenas end with their owner, never mid-run.** No `reset()` and no freeing of arena memory by scope, because deciding when windows are dead is lifetime tracking, which next-lang avoids (borrow-checker territory). An arena lives as long as its job, run or enclosing struct and is dropped whole. Long-lived servers use one arena per request or job, dropped whole. This supersedes the bulk-reset wording in decision 4 and "Why this is not a heap": the memory is released when the owner ends, not by an operation that needs a proof. Arena reuse in a loop is done with a fresh arena per iteration owner, or not at all.

## Built-in implementation (branch `text-builtin`, 2026-11-04)

Implemented in the self-hosted compiler (`selfhost/windows.nl` plus small hooks), following the decisions above. Names are provisional and
each is a single token to rename: the type `Window<arena>` (searched as `"Window"` in `compiler_types.nl`, `pool_owners.nl`,
`compiler_tables.nl`, `compiler_unsupported_core_sys.nl`) and the arena `arena<N>` (parser, `collections.nl`).

- **Arena**: `var src: arena<64000000> = arena {}`, a local, parameter or struct field. It is a pool of one-byte octets (so pass-by-address,
  never copied, owner machinery and the "one struct value holding pools" rule all apply), with a 24-byte header (bytes used, capacity, open
  builder mark) and N contiguous bytes. N is at most 2 GiB (windows are 32-bit). `src.used()` reports the bytes used; exhausting N fails
  loudly (`arena capacity exhausted`).
- **Window**: one `long`, start in the high 32 bits and length in the low 32; plain data, copied freely, no address. `Window<src>` names its
  arena as an owner, checked like a pool id; a wrong arena is the build error `expected b.Window, got a.Window`. Read-only: nothing writes
  into an arena except appending at its end.
- **Operations**: `src.add(bounded)`, `w.len()`, `w.slice(a..b)` (no copy), `w[i]`, `==` `!=` `<` `<=` `>` `>=` (by content; the other side may be a
  bounded Ascii/Bytes value, compared without copying), `w.to_bytes()` (checked copy-out to the expected `Bytes max N`/`Ascii max N`),
  `print(w)`, `w.starts_with(x)`, `w.ends_with(x)`, `w.contains(x)`, `w.find(x)` (index or -1); `x` is a window of the same arena or a bounded value.
  Operations that read bytes find the arena through the window's owner: the owner pass stores the arena's binding in the node, and for a
  struct-field arena it uses the function's one value of that struct. Not done: interpolation `"{w}"`, `Text` (UTF-8) copy-out.
- **Generated text** lives in the same arena: `src.begin()`, `src.append(bounded or window)`, `src.push(byte)`, `src.finish() -> Window`.
  One builder is open per arena at a time. This is a **run-time rule** (the open mark is in the arena header): a second `begin`, an `add`
  while a builder is open, and `push`/`append`/`finish` with none open fail with `arena builder misuse`. No compile-time tracking.
- **Reset: deferred pending maintainer decision.** An arena lives and ends with its owner; there is no `reset`, `clear` or window assignment.
  The implementation needs no lifetime reasoning: a window cannot outlive its arena because the arena is a pool (cannot be returned or copied)
  and the window type names a parameter, local or field owner.
- **Map keys by content: not done, and refused.** Map functions are generated per map type as IR over key bytes (`hash`, `hashslot`, `same`, `find`, `get`, `set`,
  `remove`, `compact`); hashing a window needs the arena's bytes, which the map type does not know. Supporting it means threading an arena
  pointer parameter through those eight functions and their call sites (the owner pass would supply it as it does for `w[i]`). A key record that
  stored an arena address in the slots was rejected: it would put maps and arenas into lifetime tracking. Until then a window, or a struct/array
  holding one, is refused as a map key, in `==` of aggregates, in `print` of aggregates and in `expect a == b` (they would compare or show the
  packed position, not the text). `@nlw_hash` (FNV-1a over a window's bytes) is already emitted for the map work.
