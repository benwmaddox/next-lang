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
