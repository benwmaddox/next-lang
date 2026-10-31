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
| 12 | Heredoc/regex edits of source with backslashes keep mangling escapes in my own tooling (not the language) | tooling | 8+ | T: use file-based edits |
| 13 | An unused `Result` is an error, but a call used only for its side effect still needs a binding | `let closed = env.net_close(...)` | 8 | same as 2 |
| 14 | No way to give a function a default argument or named arguments; `Row { key: -1L, found: false, v: 0L, price: 0L, name: Bytes.empty() }` is repeated | cache init, ask messages | 4 | L: struct defaults exist for fields; use them for these literals |

(Entries 1, 2, 5, 7, 8 are the candidates for the first language fixes: they are hit constantly and touch every file.)

## Campfire-specific entries

None yet. Add them as slices are built.
