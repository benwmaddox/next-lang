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

## Friction fixes after slice 1 (2026-10-31)

- **16** the seed is refreshed (`scripts/update-seed.sh`), so `selfhost/*.nl` can use `while`, struct arguments in `spawn` and the
  rest; refresh it after every language change the compiler's own code wants to use. Still worth: an error naming the seed.
- **17** the "IR buffer limit exceeded" error now points at the function whose code filled the buffer ("the generated code filled
  the compiler's output buffer in this function (look for a very large value, or a construct that is expanded again and again)").
  Plumbing only; I could not provoke an overflow to see it fire (60,000-element array literals are fine).
- **18** the error for a stored `.bytes()` view now says what to do instead (`name[i]`, `name.len()`; **`Ascii` and `Bytes` can be
  indexed directly**, which the app now uses). A view in a `let` is still refused.
- **14** needed no change: struct field defaults already exist (`id: long = 0L`, `name: Bytes max 32 = Bytes.empty()`) and give
  `User {}`; the app uses them, and the template generator now ignores defaults when it reads the types.
- **15** the message already says "choose a different name"; left as is.
**23 fixed the same day by multi-line string literals** (`"""..."""`, see below). Still open: 3 (done by `discard`), 4, 6 (string
interpolation), 9 (generators into the compiler), 10, 11, 12, 21 (redirects). Written then as open, and now fixed, **23**: SQL queries are single-line literals of 300+ characters (a literal cannot span lines, and `db_row` requires a
literal so it can be checked when built). Options: a line continuation in string literals, adjacent literals joined, or named
queries in a `.sql` file referenced by name. It needs a decision, because the build-time check reads the literal's text.

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

## Multi-line string literals (Ben's suggestion, 2026-10-31)

`"""..."""` is a string literal that may span lines. The line breaks and the indentation are part of the text; the ordinary
escapes work; a quote, or two in a row, is just text; the text ends at the next three quotes. The lexer makes the token look
like an ordinary string whose content is the text, so every reader of a literal's content works unchanged (lengths, `Ascii`
types, constants). `Env.db_row` / `db_rows` take them, and the build-time query check reads them with the line breaks as
spaces (an error is reported on the line the literal starts). The Campfire queries are now written over several lines
(`apps/campfire/main.nl`). Tests: `tests/py/test_multiline.py`.

## Round 3 of fixes (2026-10-31): what is closed, what is a project

- **21** done: `Env.http_set_header(connection, "Location: /rooms/7")` adds a header line to the next response; a 302 with a Location is a
  redirect, `Set-Cookie: ...` lines (several allowed) set cookies. A line with a line break, an empty line or a line with no colon
  is refused (header injection), and queued lines are sent once and forgotten. More status reasons are known (201, 204, 302, 303,
  401, 403, 422, 429). Tests: `tests/py/test_http_redirect.py`.
- **11** done: `\r` is an escape now (`"a\r\nb"`); the others were already there (`\"`, `\`, `\n`, `\t`, `\0`, `\xNN`).
- **4** closed as by design: `none` (and `some`, `ok`, `err`) are the constructors' names; the error says to choose another name.
- **10** closed: services read as `cache.get(id)` with method syntax, and the checks in `svc.py` find both spellings.
- **12** closed: it is about my own shell and regular-expression editing, not the language; the Edit tool avoids it.
- **3** closed: `discard x.send(v)`.
- **Projects, not fixes:** **6** string interpolation (`$"{id}:{name}"`, a typed bounded text; the compiler needs a lexer mode for
  the braces, a node kind, a bound computed from the holes and an emitter; templates cover the HTML and JSON cases) and **9** the
  Python generators `tools/tmpl.py` and `tools/svc.py` moving out of Python (into the compiler, or into next-lang programs the
  driver builds and caches the way it caches the query checker). Each is days of work, not an afternoon; both need a decision on
  the target form first.

## Round 4: slice 2 (sign in and out)

New generic capabilities, all with tests (`tests/py/test_http_identity.py`): `Env.http_body` (the request body, first 4096 bytes),
`Env.http_peer` (the peer's address as text), `Env.random_token(n, out)` (base-58 from the system's random source),
`Env.password_verify(hash, password)` (bcrypt as Rails writes it, by the system crypt, compared in constant time; links `-lcrypt` only
when used) and `Env.db_exec("insert ...", params)` (a literal statement, checked against `schema.sql` when the program is built,
parameters bound like `db_row`'s; returns the rows changed). DELETE, PUT and PATCH are methods 4, 5 and 6.

Campfire: `GET /session/new` (form), `POST /session` (form body parsed with percent-decoding; a deactivated user or wrong password
is sent back to `/session/new?failed=1`; success inserts a session row with token, address and user agent and redirects home with
`Set-Cookie: session_token=...; HttpOnly; Path=/; SameSite=Lax`), `DELETE /session` (row deleted, cookie cleared), and every other
page redirects to the form when nobody is signed in. Not done: the bans table (it is not in the snapshot's schema), first-run setup,
CSRF tokens, rate limiting of sign-in.
Friction: `ok` as a variable name collides with the `ok` constructor (same family as entry 4); form-urlencoded parsing had to be written
in the app (a candidate for a small library).

## Round 5: the generators out of Python (#9)

`tools/gen/tmpl` and `tools/gen/svc` are next-lang programs (about 1,500 and 1,100 lines) that replace `tools/tmpl.py` and
`tools/svc.py`. `scripts/nlc` builds each with the compiler on first use into the cache (again when its sources, the compiler or the
runtime change) and runs it for packages with `.tpl` or `.svc` files; a build needs no Python now. Both produce byte-identical output and
identical error messages to the Python versions on 49 template cases and 26 service cases plus the real packages
(`tools/gen/compare_tmpl.py`, `tools/gen/compare_svc.py`, run with the built binary as the argument). The Python files stay as the
reference for those comparisons (and the unit tests that import them) until the corpus is turned into golden files.

Compiler bugs found by writing them (both worked around; to fix):
- **24** `for entry in files { ... env.fs.join(package, entry.name) ... }` over a list<DirEntry> gives the first element's path every time;
  `for i in 0L..files.count() { let entry = files[i] ... }` is right. The same loop-view family: `for edge in a { discard b.push(edge) }`
  (pushing the loop element into another list of the same type) generates IR with an undefined local and clang rejects it.
- **25** a `Bytes` stored in a struct reached through a `write` parameter cannot be grown (`grow` is for builders only), so a program with
  several output buffers keeps them as `list<byte, N>` fields or passes each as its own `grow` parameter.

## Round 6: string interpolation (#6)

`$"user {id}: {name} scored {score}"` is built. The lexer turns it into a `Dollar` token, `String` pieces (each borrowing the
characters beside it as its quotes, like a multi-line string), `LBrace ... RBrace` around each hole and an `InterpEnd` token; the parser
makes a left-leaning chain of `+` over the pieces and one call node per hole whose callee token is the `$`. The checker treats such a
call as `str`: a number becomes its digits, and `Ascii` or `Text` is copied as it is. So the type is the concatenation the checker already
bounds (`Ascii max` the sum of the pieces, with each number at its type's longest) and the code is the concatenation and formatting
that exist. `{{` and `}}` are literal braces; a hole is any expression. Holes take int, long, byte, Ascii and Text; a bool, a `Bytes`
or a struct is an error that says so. Still to do: `Bytes` holes (concatenating `Bytes` with `Ascii` into `Bytes`, which Campfire's
code wants), bool holes, the format options (`{n:8}`, `{n:x}`) and appending straight into a builder without a temporary.
Tests: `tests/py/test_interpolation.py`.

### Round 6, second part: flat code, `Bytes` and bool holes, formats, appending without a temporary

- **Flat.** The parser still makes the chain of `+`, but every node is marked (`extra` is `INTERP_MARK`) and the code is written by the
  chain's root alone (`selfhost/interpolation.nl`): each piece is copied, or its number formatted, straight to its place in one
  destination. The `+` nodes and the hole calls under a flat root have no code and no storage of their own (the region planner skips
  them), so a chain of n pieces is n writes with no temporaries and no prefix copied again. Before, each `+` made a value and copied
  the growing prefix.
- **Into a builder.** `out.try_append($"...")` (a `Bytes` or `Ascii` builder) checks once whether the builder has room for the chain's
  largest value; if so the pieces are written to the builder's tail and its length is set, with no intermediate value. If not, the
  chain is built in its own storage first and appended with the exact length, so `Full` is reported exactly as before (a value that
  fits is never refused because its worst case would not).
- **Holes.** int, long, byte, bool (`true`/`false`), `Ascii`, `Bytes` (the result is `Bytes` when a hole is `Bytes`, and an
  all-`Ascii` chain takes the type its context wants), `Text` (a chain with `Text` keeps the pairwise concatenation, because
  code points have to be counted: the one place a nested form is kept). A struct or a double is an error.
- **Formats.** `{n:8}` (padded to width 8, numbers and text), `{n:08}` (zero-padded), `{n:x}`, `{n:b}`. The width is a literal.
  `{n:8}` for a number is not available inside a chain that also holds non-ASCII text.
- Campfire's sign-in now builds its cookie header with one `try_append($"Set-Cookie: session_token={session.token}; ...")`.

### Round 6, third part: Text chains are flat too

A chain with non-ASCII text (a `Text` value) is written by the same flat code. Alongside the byte offset it keeps a running count of code
points: a literal piece and a number or bool count what they write, an `Ascii`/`Bytes` hole counts its bytes, a `Text` hole says how
many it holds (padding adds up to its width). The root stores both numbers in the `Text` header, and `try_append` to a `Text` builder
checks the builder's byte limit and its code-point limit together before writing into its tail. Nothing in interpolation uses the
pairwise concatenation now, and `{n:8}` works in `Text` chains.

Open question (Ben): why `Bytes` at all in these chains? `Bytes` appear because the database layer (`db_row`/`db_rows`) and the
network reads (`http_header`, `http_body`, `http_peer`) fill `Bytes` fields only. Campfire's names and message bodies are
text that came through those, so they stay `Bytes` and a chain holding one is `Bytes` (raw, not checked as UTF-8, no code-point
count). Making them `Text` means checking UTF-8 where the data enters (SQLite does not guarantee it; a request can send anything), so a
bad value needs a rule (refuse the row, replace the byte, or fail the request). Proposed next step: allow `Text` fields in
`db_row`/`db_rows` and `Text` destinations for header/body reads, validated when read.
