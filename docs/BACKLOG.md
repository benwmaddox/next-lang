# Backlog: language and compiler work the typescript-go port asks for

Source: converting the Go typescript compiler with go2nl (D:\code\go2nl, docs/findings.md,
table "What this implies for next-lang"). next-lang is a proving ground; some concepts may
change. Order of work for each item: make it work, then make it right, then make it fast.
Status 2026-11-03: **approved** by the maintainer unless noted.

## Approved

1. **Or-patterns in `match`.** `A | B => body` so a case that handles several variants
   does not repeat its body. go2nl's interface type switches with several types per case
   repeat the body once per type today. Check exhaustiveness as before; bindings in an
   or-pattern must have the same names and types in every alternative.
2. **Unsigned types, all together** (PLAN.md already schedules this as one step).
   `ushort`, `uint`, `ulong` (and `byte` becomes the unsigned 8-bit type; `sbyte`,
   `short` with them). Checked arithmetic including unsigned underflow (`0u - 1u` fails),
   casts written explicitly and checked when narrowing, `unchecked(...)` / wrapping
   operators for the low bits (hashes, flags), shifts and bitwise operators, literals with
   suffixes (`5u`, `5UL`), printing and parsing, ranges and storage widths as for `int` and
   `long`. Needed for typescript-go: flags (`uint32`), ids and hashes (`uint64`, xxh3),
   3,000+ unsigned sites in the checker.
3. **Float text in the core library.** Shortest round-trip printing of `double` (Ryu-style)
   and correctly rounded parsing (Eisel-Lemire-style, with a slow exact fallback), in plain
   next-lang. Replaces go2nl's hand shims for `jsnum.FromString` and `Number.String`, which
   are exact only for whole numbers and short decimals. Oracle: the parse-number test data
   and round-trip checks named in PLAN.md (F1).
4. **Growable text arena.** Text that does not need a per-value maximum: a per-job arena of
   bytes where a text value is plain data (arena, start, length) or an id, so source files of
   1-16 MiB and thousands of small strings can coexist without every value reserving the
   worst case. Read access gives a slice-like window of the same data (no borrowed
   reference: the window is the triple, copied freely). Design note first (how it composes
   with `Text`, `Ascii`, `Bytes max N`, interpolation, maps keyed by text, and the
   allocate-at-startup rule: the arena's size is declared and fixed, exhaustion is visible).
   go2nl would then give each Go `string` an arena window instead of a `Bytes max N`.

## Already done for this effort (next-lang `dx/agent-docs-and-check`)

`float` (32-bit); `pool.set`; owner-checked pool ids (`Id<nodes>`); several pools and pools
as struct fields; `pool[id].f` places; fixes for the nested-call pool miscompile, enum list
literals, list-of-arrays and nested for-each.

## In progress

Maps with struct, id and list keys and values; pools in function results; non-scalar
constants; `Bytes max N[3]` parsing (branch `rich-maps`).

## Open questions (maintainer to decide)

- Interior pointers (`&n.Node` where `Node` is embedded in a bigger struct): keep go2nl's
  split-into-two-pools rule, or a language concept? See go2nl docs/embedded-split.md.
- Incremental / modular builds: see the recommendation in go2nl docs/findings.md.
- Iterators: probably no language change; go2nl converts range-over-func by inlining.
- Small: `Option<Id<P>>` as the idiomatic "maybe a link" and `none` as a field default;
  letting a temporary be a `write` argument (go2nl uses explicit temporaries today).

## Principle: explicit environment (2026-11-03)

No subtle hoisting of values into a closure: a function sees only what it is given as arguments
(DESIGN.md, "Explicit environment, never hoisting"). Value types of this kind are welcome: a
*view* (reference + start + end), a *cursor* (iterator state), an *environment record*
(captured values + the id of the named function). Open: names for the family (View, Cursor,
Env_* are the proposals), and whether next-lang gets a built-in `View` type.

Open question that follows from it: DESIGN.md's *scoped blocks* (`db.read { }`,
`transaction { }`, `parallel for` bodies, a page's `for` and `if`) "may read the surrounding
locals", which is implicit capture by another name (the compiler makes a helper whose context
is passed explicitly, but the programmer does not see that). Decide whether to keep them
as they are, make the context visible in the syntax, or list the read locals at the block.

### Decided 2026-11-03: option C, `using (...)` on blocks that run elsewhere or later

`db.read`, `db.transaction`, `transaction`, route tables and `parallel for` bodies list the
enclosing function's locals they use: `db.read using (room_key) { ... }`. Using an unlisted
local is a build error naming it. A block using no locals needs no list. A page's `for` and
`if` run in place and are unchanged. Wording in DESIGN.md ("Scoped blocks aren't closures,
and list what they use") and the examples in DESIGN.md / EXAMPLES.md are updated. Not
implemented yet: the self-hosted compiler has no scoped blocks at all; implement the syntax
and the unlisted-local check together with the first block (`db.read`).

### Text arena decisions (2026-11-04)

Separate unbounded text type; always names its arena; read-only once made; one window
representation; generated text in the same arena; 32-bit start and length. Library stage 1
(`tests/c_runtime/text_arena`) and design note `docs/design/text-arena.md` are merged. Next:
the built-in type and sugar, content hashing for map keys, `starts_with`/`find`, interpolation,
arena reset, usage counter. Question 4 decided: accept dead bytes until bulk reset; long-lived edited state keeps `Text max N`.

### Append-only bounded text (maintainer leaning, 2026-11-04; not yet decided)

`Text max N`, `Ascii max N` and `Bytes max N` become append-only apart from whole-value
assignment: no index assignment or range replacement (today index assignment on `Ascii` and
`Bytes` is accepted but miscompiled: `b[0] = 72` clears `b[1]..b[3]`, `s[1] = 69` has no
effect; `Text` already refuses it). No `clear()`: memory is dismissed by normal scoping and
bump allocation (a value declared inside a loop body is fresh each iteration and its storage
goes with the scope mark), and `s = ""` stays as ordinary whole-value assignment. Mutable
byte data is `list<byte, N>` or `byte[N]`. Windows stay arena-only. To do if adopted: make
index assignment on `Ascii`/`Bytes` a build error, fix what in `selfhost/` and `core/` used
it, update LANGUAGE.md, and map Go `[]byte` to `list<byte, N>` in go2nl. Open: `truncate(n)`
(not allowed in this proposal).

### Text arena: no reset, arenas end with their owner (decided 2026-11-04)

No `reset()` and no scope-based freeing of arena memory (it needs lifetime tracking). Arenas
are dropped whole with their owner (job, run, struct). The append-only bounded-text proposal
above is still only a leaning.

### Small ergonomics found testing text appends (2026-11-04)

- `Text` has no `+=` (`Ascii` does): "compound assignment requires int, long or double". Make `Text +=` (and interpolation append) work like `Ascii`.
- Appending one byte to `Ascii`: `outer += a[i]` fails ("expected Ascii, found byte"). Add `push(byte)` for `Ascii` (checked < 128) and for `Text`, as `Bytes` has.
- `a.slice(999..1000)` of an `Ascii max 1000` has type `Ascii max 1000`; with constant range bounds the result type could be `Ascii max 1`, so it appends into `Ascii max 100` without `try_append`.
- The error "expected Ascii, found Ascii" when only the maxima differ should print the maxima (`Ascii max 100` vs `Ascii max 1000`).
- Measured OK: a value declared inside a loop body is fresh each iteration with flat memory (3,000,000 iterations x 1,000 appends: peak RSS 1.6 MB), so loop-scoped declaration is the way to reuse a buffer without `clear()`.

- One character out of text (maintainer, 2026-11-04: `last()` is fine; a single item of `Ascii` is itself `Ascii`): keep `a[i]` as a byte for `Ascii`/`Bytes` (arithmetic; Go's `s[i]` is a byte) and add explicit character operations: `last()` / `first()` returning `Ascii max 1` for `Ascii` and `Text max 4` for `Text` (O(1)), `char_at(i)` for `Ascii` returning `Ascii max 1` (`Option` if out of range), and a checked byte-to-`Ascii max 1` conversion (fails for 128 or more). Names are proposals. `Text` stays unindexable by position (the n-th code point needs a scan).

- **DECIDED 2026-11-04** (maintainer: "not just a proposal any more"):  `Ascii` indexing `a[i]` returns `Ascii max 1` instead of a byte; `Bytes[i]` stays a byte (raw data). Benefit: no character literals needed (`a[i] == "x"`, `"0" <= a[i] && a[i] <= "9"`), and Go `c == 'x'` converts readably. `Ascii max 1` gets `to_byte()` (fails unless exactly one character) for arithmetic; `Ascii`/`Text` get `to_bytes()` (copy into `Bytes max N`, `4N` for Text). The compiler should optimise `a[i].to_byte()` and `a[i] == "x"` to a plain byte load/compare with no temporary. `Text` stays unindexable by position (code-point scan or UTF-8 breakage); `first()`, `last()` and `for ch in t` (each `ch` a `Text max 1`) cover it. Note `to_byte()`/`to_bytes()` differ by one letter. go2nl is unaffected: Go strings become unbounded windows whose `w[i]` is a byte, like Go.

Approved text ergonomics (2026-11-04), to implement together: `Ascii` indexing returns `Ascii max 1` (`Bytes[i]` stays a byte); `to_byte()` and `to_bytes()`; `first()`, `last()` on `Ascii` (`Ascii max 1`) and `Text` (`Text max 4`); `Text +=`; `push(byte)` and appending a one-character value to `Ascii`/`Text`; constant-range slices get a tight maximum; error messages print maxima. DECIDED (2026-11-04, maintainer: append-only until a real need for byte-level change): `Ascii`, `Bytes` and `Text` are append-only; index assignment on `Ascii`/`Bytes` becomes a build error (it is accepted but miscompiled today); no `clear()`; whole-value assignment and appends stay; mutable bytes are `list<byte, N>` or `byte[N]`.
