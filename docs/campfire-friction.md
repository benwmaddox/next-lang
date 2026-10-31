# Campfire friction log

One entry per snag in writing next-lang application code: what, where, how many times hit, and what would remove it. "Fix class":
L language or compiler, S standard library or runtime capability, T tooling, D documentation, N nothing (acceptable). Counts are
incremented each time the same snag costs time again.

## Status after the first round of fixes (2026-10-31)

Fixed in the language (tests in `tests/py/test_friction.py`):
- **1** struct literals are allowed inside the parentheses of any call, even in a `match` head or an `if` condition
  (`match box.send(Msg { ... })`).
- **2, 13** `discard` now drops any plain value (a number, bool, struct) and a mailbox send, besides the built-in
  operations whose only error is Full; it still refuses an arbitrary `Result` or `Option` (`discard env.net_close(c)`,
  `discard box.sender().send(msg)`).
- **7** `spawn` accepts structs of plain data (numbers, enums, text, bytes, lists, arrays, other such structs), copied into the
  job's argument block; services pass `Cache` and `Database` handles as they are.
- **8** `while` works on the C runtime too (it was refused only there); service loops and `serve` use `while true`.
- **5** needed no change: `type Body = Bytes max 512` already works, including `grow Body` parameters. It was not known, which
  is its own finding (documentation).
Still open: 3 (`try_send` for a fire-and-forget send is now `discard x.send(v)`; probably done), 4, 6, 9 (generators), 10, 11,
12, 14.

## Campfire slice 1 so far

| # | Snag | Where | Hits | Fix class and idea |
| --- | --- | --- | --- | --- |
| 15 | `none` as a variable name is refused (collides with the bare enum case); hit again naming the "no rows" count in a test (4th hit of #4) | test programs | 4 | L: allow shadowing of a bare case by a local, or an error text that suggests a name |
| 16 | The compiler's own sources cannot use a language feature the seed does not have (`while` was enabled for programs, but `selfhost/*.nl` had to keep `for ... break` until the seed is refreshed with scripts/update-seed.sh) | compiler work | 1 | T: say so in the error ("the seed compiler does not support X; use Y or refresh the seed"), or refresh the seed after each language change |

Slice 1 capabilities added while writing the first code: `Env.db_rows` (several rows into `list<Row, N>`, limit checked when built),
template loops (`{#for r in rows}`, size = count times the body), `Env.http_header` (request headers, cookies).

Observed in use (positive): the build errors named the place and what to do for the new checks (limit missing or larger than the
list; string literal with a newline "escape it as \n"; a struct without the function for a method call). `if env.http_write(...) < 0L
{ break }` reads well now that results need no throwaway `let`.

Observed (negative, counted in the table below): the quoting of backslashes in my shell/regex edits corrupted source three more
times this stretch (#12 now 11+ hits): the tests directory needs a helper that writes files verbatim, and the Edit tool should be the
default for anything with escapes.

## Campfire slice 1: the room page

| # | Snag | Where | Hits | Fix class and idea |
| --- | --- | --- | --- | --- |
| 17 | "self-hosted LLVM IR buffer limit exceeded" with no hint of the cause: a `write` list or struct parameter handed to `db_rows` made the compiler emit without end | `rooms_of(env, user, rooms: write list<Room, 100>)` | 1 (an hour) | L: say which function or node was being emitted when the buffer filled; fixed the cause (write aggregates as query destinations) |
| 18 | A `.bytes()` view cannot be kept in a `let` ("temporary and cannot be stored"); a helper needs `name.len()` and `name.bytes()[i]` repeated | `cookie_value` | 2 | L: allow a view in a `let` while its owner lives |
| 19 | A column called `type` cannot be a struct field (keyword), so the query needs a subselect with an alias | rooms.type | 1 | N: aliasing in the query is fine; the build-time check caught the first attempt (`no such column: kind`) at once |
| 20 | **Two call sites with the same row type shared one prepared statement** (the runtime told sites apart by the address of a constant table, and LLVM merged identical tables): the second query ran the first's SQL. Showed up as an empty sidebar and a 404 | db_row / db_rows | 1 (long) | fixed (tables are not `unnamed_addr`); regression test in test_db_rows. Lesson: a runtime cache must not key on addresses of constants |
| 21 | No `Env`-level way to say "this user is not signed in, redirect to /session/new"; slice 1 answers 401 | pages | 1 | S: response headers and redirects (slice 2) |
| 22 | The plain `type Page = Bytes max 196608` alias worked everywhere it was used, including template helpers and the `grow` parameter | pages | 0 | positive: aliases fix #5 |

## Seeded from the web work so far (bench/web, services, templates), 2026-10-31

| # | Snag | Where | Hits | Fix class and idea |
| --- | --- | --- | --- | --- |
| 1 | A struct literal cannot be the scrutinee or an argument inside a `match` head (`match q.send(Msg { ... })` is a parse error); every message needs a `let` first | mailbox sends, cache fills, db rows | 6+ | L: allow struct literals in match scrutinees |
| 2 | Ignoring a result needs `let sent = ...` (an unused variable) or a `match` with two empty arms; `discard` accepts only a few built-in operations | every send, every `http_write`, `net_close`, `Cache_fill` | 20+ | L: `discard` for any result, or `_ = expr` |
| 3 | `match x.send(v) { ok(_) => {}, err(_) => {} }` for a fire-and-forget send is five lines | all mailbox sends | 10+ | S: `try_send` returning bool; or L: `if let` |
| 4 | A variable named `none` (or `step`, `index` in generated code) collides with a bare enum case or loop variable | tests, generated loops | 3 | N, with better error text; generated code uses `svc_turn` |
| 5 | A bounded type's maximum must be repeated exactly on every function that takes it (`grow Bytes max 512` on every helper) | templates, builders | every helper | L: a named type alias for bounded types (`type Body = Bytes max 512`) |
| 6 | No string interpolation in the self-hosted compiler (`$"..."` is designed, not built); numbers are appended with hand-written helpers | JSON/HTML before templates | 5 | L: build interpolation; templates cover part of it |
| 7 | `spawn` accepts only numbers, bools, `Env` and mailbox handles; a struct that wraps a handle (`Cache`) is rejected, so the wrapper is unwrapped and rebuilt at each job boundary (`serve(env, conn, cache_inbox)`, `let cache = Cache { inbox: cache_inbox }`) | acceptor and serve tasks | 4 | L: allow structs of allowed fields |
| 8 | Loops are `for i in 0L..4000000000L { ... break }` because `while` is unsupported on the C runtime | every service loop, retry loop | 10+ | L: `while` / `loop` |
| 9 | Two generators in Python (`tools/tmpl.py`, `tools/svc.py`) exist because the compiler has no templates or services; users need Python to build, and errors point at generated files | templates, services | constant | L: move into the compiler |
| 10 | Services call each other with a spelling that depends on the surface (`Cache_get(cache, id)` or `cache.get(id)`); checks in `svc.py` had to learn both | services | 2 | L: done for structs by method syntax; the check should move into the compiler too |
| 11 | Escape sequences in string literals are limited (`\"`, `\\`, `\n`, `\t`, `\0`, `\xNN`); building HTML/JSON text by hand needs care | templates, tests | 3 | N; templates remove most of it |
| 12 | Heredoc/regex edits of source with backslashes keep mangling escapes in my own tooling (not the language) | tooling | 11+ | T: use file-based edits |
| 13 | An unused `Result` is an error, but a call used only for its side effect still needs a binding | `let closed = env.net_close(...)` | 8 | same as 2 |
| 14 | No way to give a function a default argument or named arguments; `Row { key: -1L, found: false, v: 0L, price: 0L, name: Bytes.empty() }` is repeated | cache init, ask messages | 4 | L: struct defaults exist for fields; use them for these literals |

(Entries 1, 2, 5, 7, 8 are the candidates for the first language fixes: they are hit constantly and touch every file.)

## Campfire-specific entries

None yet. Add them as slices are built.
