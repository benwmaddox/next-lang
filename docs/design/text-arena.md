# Text arena: unbounded text as windows into an arena

Status: design note, 2026-11-03. Stage 1 is implemented as a library written in next-lang itself
(`tests/c_runtime/text_arena/text_arena.nl`, no compiler change); the built-in spelling below is the target. Backlog item 4.

## Why

`Bytes max N` is inline at its maximum (DESIGN.md, "Stored values are inline at every bound"): every value reserves N bytes and is
copied by value. go2nl converts Go `string` to `Bytes max N` with one N for a 1-16 MiB source file, so every string reserves that much,
frames are huge and scanner time is quadratic (407 KB: 206 ms vs Go 3.8 ms; 1.63 MB: 5.1 s). A string longer than N fails. Text should
not need a maximum.

## The rule

- `Text max N`, `Ascii max N`, `Bytes max N` stay as they are: **inline at the declared maximum and mutable** (in-place append and
  replace). Use them for small bounded fields (identifiers, names) and for long-lived state that edits text repeatedly.
- Text **without** a maximum is the unbounded form. It is a **window**: plain data (start, length; 8 bytes in stage 1), copied freely,
  never owning bytes. It **names its arena as an owner**, like `Id<nodes>`. Built-in spelling: `Text<src>` (UTF-8) and `Bytes<src>`
  (raw); stage 1 spells the raw form `Id<src>`. A window of arena A cannot be used with arena B (build error from the pool-owner check:
  `expected b.Id, got a.Id`). There is never an ambient arena: every operation names the arena (`src.add(...)`).
- An **arena** is `pool<byte, N>`: one region of declared capacity N, owned by its declaring local, parameter or struct field, never
  copied (pools are passed by address). Windows are ranges of it.
- **Unbounded text is immutable.** A window's content never changes; "editing" builds a new window.

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

## Operations

All take the arena first. Exhaustion, a bad slice and a bad index fail the program.

| Operation | Stage 1 library | Built-in target |
|---|---|---|
| create from literal / bounded value | `arena_add_ascii(src, s)`, `arena_add_bytes(src, b)` | `src.add(s)` |
| length | `arena_len(src, w)` | `w.len()` |
| slice, no copy | `arena_slice(src, w, a, b)` | `w.slice(a..b)` |
| byte at | `arena_at(src, w, i)` | `src[w][i]` |
| equal / order / hash by content | `arena_equal`, `arena_less`, `arena_hash` | `==`, `<`, map key hash |
| starts_with, find (offset or -1) | `arena_starts_with`, `arena_find` | methods |
| checked copy-out to bounded | `arena_to_bytes_256`, `arena_to_bytes_4096` | `w.to_bytes()` (N from the expected type) |
| print | `arena_print(env, src, w)` | `print(w)`, interpolation |
| builder | `m = arena_begin(src)`, `arena_push`, `arena_append_ascii/bytes/window`, `arena_finish(src, m)` | `src.begin()` .. `.finish()` |

Departure from the first sketch: `w[i]` needs the bytes, and a window carries no address (DESIGN.md: stored data holds no addresses; a
window is (start, length) plus a *static* owner), so byte reads name the arena. A built-in `==` between windows of the same owner would
read the arena known from the type.

Conversions: bounded -> unbounded is a copy into the arena (`add`). Unbounded -> bounded is a checked copy-out that fails when too long.
Comparison, ordering and hashing are by content across both kinds (the built-in compares a window with an inline value without
copying). A window may be a struct field, a pool or list element, or a map key (hash by content): plain data under the owner rule. Stage 1
gives `arena_hash`; map keys by content need a compiler hook and are not done.

## Builder

A builder writes at the arena's end, so **one builder is open per arena**: `begin` returns the start mark and `finish(mark)` the window of
everything appended since. Other appends in between would interleave, and the built-in `begin` should hold the arena's write access until
`finish`. Builders with their own region (a second arena for generated text) allow several at once.

## Immutability and zero-copy slices

Because a window's bytes never change, any number of windows alias the same bytes safely: a substring is a smaller (start, length), with
no write-through hazard and no copy. The arena only grows, so windows never dangle before a reset. The library never overwrites arena
bytes (`pool.set` is not used).

## Limitation

The arena is append-only: replacing an unbounded text field allocates new bytes and the old ones stay until the arena is reset. Unbounded
text suits per-run/per-job data and immutable inputs. Long-lived mutable state that edits text repeatedly should keep `Text max N`.
Stage 1 limits: start and length are packed in one long (arena up to 2 GiB); the library window type `Id<src>` is the same type as the
arena's own byte slot ids (the built-in `Text<src>` would be distinct); the helper `arena_slot` is the one place that builds an id by arithmetic.

## Go port mapping (stage 3 sketch)

- Go `string` -> unbounded window `Text<src>`; `s[a:b]` -> `slice`; `len(s)` -> `len`; `s[i]` -> byte read; `==`, `<` -> content compare.
- `strings.*` shims (`HasPrefix`, `Index`, `Contains`, `TrimPrefix`) -> `starts_with`, `find`, `slice` over windows.
- Go `[]byte` -> `Bytes max N` or `list<byte, N>` (mutable, bounded). `[]byte(s)` -> checked copy-out. `string(b)` -> `add` (copy into the arena).
- `strings.Builder` -> arena builder.
- The scanner's `text` field is a window into one source arena (loaded once, immutable); token values are windows into it, or into a
  generated-text arena when escape processing changes the bytes.

## Stage 1 status

Done: library with every operation above including the builder; test `tests/c_runtime/text_arena` (5 MB arena, 3 million slices, a
read-only 5 MB arena through 2000 recursive calls, which would overflow the stack if copied) and negative test
`tests/pool_owner_errors/text_arena_wrong_arena`. Remaining: the built-in `Text<src>` / `Bytes<src>` types and sugar, content-hash map keys,
interpolation, arena reset, UTF-8 validation for `Text<src>`, a distinct window type.
