# The language in practice: a cheat sheet

What the **self-hosted compiler accepts today**, for someone (or an agent) writing next-lang code. Every example here is in
[examples/tour/main.nl](examples/tour/main.nl), which `tests/py/test_docs.py` builds and tests, so none of it is aspirational.
[DESIGN.md](DESIGN.md) describes the whole language including parts not built yet; when the two disagree, this page and the
compiler win. Real programs to copy from: `tests/py/programs/cli_grep` (a CLI), `bench/web` and `apps/campfire` (web services).

Try things with `scripts/nlc check <package>` (type-check only, about 50 ms), `nlc run <package>`, `nlc test <package>`.
A package is a directory of `.nl` files; every file sees every other, with no imports. The package path must be relative to
the current directory.

## Types and bounds

Everything that can grow has a maximum the compiler knows. There is no heap, no null and no implicit conversion.

| Write | Meaning |
| --- | --- |
| `int`, `long`, `byte`, `bool` | 32-bit, 64-bit, 0 to 255, true/false. Literals: `5` is int, `5L` is long. Convert with `x.to_long()`. |
| `double`, `float` | 64-bit and 32-bit IEEE numbers (C runtime). `print(x)`, `str(x)` and `{x}` in `$"..."` give the shortest text that reads back as the same value, in JavaScript's layout: plain digits for 1e-6 <= |x| < 1e21 (`0.000001`, `123.456`, `100`), else `1.5e+21` or `1e-7`; whole numbers have no `.0`; `-0` prints as `0`; infinities print as `Infinity` and `-Infinity` (a plain float never holds NaN). `str_fixed(x, n)` gives n digits after the point. `text.parse_double()` is an `Option<double>`, correctly rounded for any input (`[+-]digits[.digits][e[+-]digits]` or `[+-]Infinity`; `1e999` is `Infinity`, malformed text is `none`). |
| `Ascii max 16`, `Bytes max 256` | text / raw bytes of at most that many; `Bytes.empty()` makes an empty one |
| `list<T, 4>` | at most 4 elements; `list {}` is empty. `push` returns a result that can be `Full` |
| `T[3]` | exactly 3 elements; `fill(0L)` makes one. an array of text is written `(Bytes max 16)[3]` (without the parentheses the `[3]` reads as part of the maximum) |
| `map<K, V, 8>` | at most 8 entries; `set`, `get`, `contains`, `remove`. Keys: numbers, bools, enums, text, or structs (hashed and compared field by field; `Id<pool>` keys are checked against the pool). Values: those, plus structs, arrays, lists and maps (`map<Ascii max 16, list<long, 8>, 32>`), plain bytes copied in and out. `for k, v in m` (or `for k in m`) visits the entries in insertion order (setting an existing key keeps its place; remove then set puts the key last); `k` and `v` are read-only copies, ids keep their pool, and the loop body may not set or remove on that map or pass it (or the record holding it) to a `write` parameter (build error) |
| `pool<T, 8>`, `Id<T>`, `Id<pool>` | `pool {}` is empty; `add` returns `ok(id)`, `get(id)` is an `Option` copy, `pool[id]` reads or writes an element in place (`nodes[id].parent = x`; the index must be an id of that pool; fails like list indexing on an id never added), `set(id, value)` overwrites in place and returns whether the id was in use. An id is a `long` slot number usable in struct fields; write the "no element" id as `-1L`. A pool may be a local, a parameter or a struct field (`struct World { nodes: pool<Node, 64>, labels: pool<Label, 64> }`, passed down as `write`, or as a plain read-only parameter: read-only pools are passed by address, never copied, also through nested calls and recursion), and a package may have several. `Id<nodes>` names the pool `nodes` (a local or parameter of the function, else the one pool field of that name): ids keep their pool through map `get`, for-each variables over lists or arrays of ids and `match` bindings; using an id with another pool is a build error (`expected labels.Id, got nodes.Id`), as is an id of unknown origin (arithmetic loses the pool); a negative literal or constant fits any pool. With more than one pool, ids must be written `Id<pool name>` (`Id<Node>` is only for a package with one pool). A helper over any pool takes `fn f<N>(nodes: pool<Node, N>, id: Id<nodes>)`. A function may return a pool or a struct holding pools if it builds it in place (a struct literal, `pool {}`, or a call of another such function). At most one value of a struct holding pools may exist; such a value, a pool in a list or array element, and copying or iterating a pool are refused. No `remove` yet (stale ids are not detected). |
| `arena<N>`, `Window<arena>` (built in; provisional names) | Unbounded read-only text. `var src: arena<64000000> = arena {}` (a local, parameter or struct field; N bytes, at most 2 GiB; never copied, like a pool). `src.add("literal or bounded Ascii/Bytes")` copies bytes into the arena and returns a `Window<src>` (a plain long: 32-bit start, 32-bit length). `w.len()`, `w.slice(a..b)` (no copy), `w[i]` (byte), `==` `!=` `<` `<=` `>` `>=` by content, `w.to_bytes()` (checked copy out to the expected `Bytes max N` or `Ascii max N`), `print(w)`, `src.used()`, `w.starts_with(x)`, `w.ends_with(x)`, `w.contains(x)`, `w.find(x)` (index, -1 when absent; `x` is a window of the same arena or a bounded Ascii/Bytes value, as is the right side of `==` and `<`; window on the left). Not yet: map/set keys by content (refused), interpolation, `Text` copy-out, `expect a == b` on windows (compare into a bool first). Builder: `src.begin()`, `src.append("text" or window)`, `src.push(byte)`, `src.finish()` returns the window; one builder open per arena (a second `begin`, or `add` while one is open, fails at run time). Exhausting the capacity fails loudly (`arena capacity exhausted`). A window names its arena (`Window<src>`, owner-checked like a pool id; mixing arenas is a build error `expected b.Window, got a.Window`); reading bytes uses the owner automatically when it is a local, a parameter, or a field of a struct value in the function. Arena memory lives and ends with its owner; nothing is freed mid-run and there is no reset. Test: `tests/c_runtime/text_window`; design: [design/text-arena.md](design/text-arena.md). |
| `Option<T>`, `Result<T, E>` | `some(x)` / `none`, `ok(x)` / `err(e)` |

Overflow, division by zero and out-of-range indexes stop the program with a failure; they never wrap silently.

## Declarations

```
const LIMIT: long = 3L
const ORIGIN: Point = Point { x: 0, y: 0 }       // also arrays, nested structs, text, bools, empty `list {}` / `map {}`: literals only
enum Kind { Low, High(int) }
struct Unit { name: Ascii max 16 = "x", hp: int = 10, items: list<long, 4> = list {} }   // defaults make `Unit {}` work
fn hurt(u: write Unit, amount: int) { u.hp = u.hp - amount }                              // `write` = may change it
```

A function can change only a parameter marked `write`, and the caller must pass something it owns. There are no mutable
globals: state is a local in `main` and is passed down.

## Control flow and errors

- `if c { a } else { b }`, `match v { Low => 0  High(n) => n }` (exhaustive), `for i in 0..n` (`0..=n` includes n),
  `for item in list`, `for k, v in map`, `while c`, `break`, `continue`, `return`. The last expression of a block is its value.
- `f()?` returns early with the error (works for `Result` and `Option`). `opt ?? fallback` uses the fallback when empty;
  the fallback may be `return x`, `break` or `continue`.
- `discard expr` drops a value you do not need, but only a plain value or an operation whose sole error is `Full`
  (`list.push`, `try_append`, a mailbox send). Any other `Result` must be matched or propagated.
- Statements on one line need `;` between them. Inside braces a newline is enough.

## Text

`$"{u.name}: {u.hp} hp"` builds text in place; its maximum length is computed at build time and must fit the destination.
`Ascii` is for ASCII only; use `Bytes` for arbitrary bytes. `x.count()` is the length of a list or bytes, `x.len()` of text.

Characters and bytes (tests: `tests/c_runtime/ascii_char`, `tests/c_runtime/text_chars`):

| Form | Meaning |
|---|---|
| `a[i]` on `Ascii` | one character, an `Ascii max 1` (fails when out of range). `a[i] == "x"`, `"0" <= a[i] && a[i] <= "9"` compare by content (plain byte compares in the generated code); `out += a[i]` appends it |
| `b[i]` on `Bytes` | a `byte` |
| `c.to_byte()` | the byte of an `Ascii max 1` (`a[i].to_byte()` is a plain byte load); fails unless exactly one character |
| `a.to_bytes()`, `t.to_bytes()` | copy into `Bytes max N` (`4N` for `Text max N`); not to be confused with `to_byte()` |
| `a.first()`, `a.last()` | `Option<Ascii max 1>`, `none` when empty |
| `t.first()`, `t.last()` | `Option<Text max 1>` (one code point, at most 4 bytes; `last` steps back over at most 3 continuation bytes); `Text` is still not indexable by position |
| `t += x` | appends `Text` or `Ascii` to a `Text` like `Ascii +=`: the append must be provable to fit bytes and code points, else use `try_append` (no append in loops yet) |
| `s.push(byte)` | on `Ascii` and `Text` the byte must be below 128 (a failure otherwise); returns `Result<(), Full>` like `Bytes.push` |
| `a.slice(3..4)` | with constant bounds the maximum is the range length (`Ascii max 1000` gives `Ascii max 1`), so it appends into small destinations; `Bytes` and `Text` likewise |
| `s[i] = x`, `b[i] = x`, `b[i] += x` | build errors: `Ascii` and `Bytes` are append-only (whole-value assignment and appends are fine); use `list<byte, N>` or `byte[N]` for mutable bytes |

A type mismatch between texts that differ only in their maxima prints them: `expected Ascii max 100, found Ascii max 1000`.

`sort(xs)` orders a writable list or array of numbers (bytes unsigned, floats by value) or text (bytes, then shorter first) in place; `sort_by(xs, ctx, before)` orders any list or array with the named function `before(ctx, a, b) -> bool` ("a goes before b", read-only parameters). `ctx` is an int, long or bool, or a variable or field holding a record, array, list, map or text (including a record that holds pools), passed by address and never copied; it may not be, or contain, the list being sorted. Both are stable merge sorts: O(n log n), with scratch space on the data stack the size of the list.

## Tests

```
test "hurt lowers hp" { var u = Unit {}; hurt(u, 4); expect u.hp == 6 }
```

`nlc test <package>` runs each test in its own process and prints `ok`/`FAIL` plus a summary. Tests can sit in any file.

## Programs and the outside world

`fn main()` or `fn main(env: Env)`. `print(x)` writes a line. With `env`: `env.args()`, `env.getenv(name, buf)`,
`env.stdin_read(buf)`, `env.out.write(bytes)`, `env.exit(code)`, and the network, HTTP and database calls the web programs
use (`env.net_listen`, `env.http_read`, `env.db_row`, ...). `package.toml` lists the capabilities a package may use:
`capabilities = ["env", "out"]`.

Concurrency is by **jobs and mailboxes**, not shared memory: `spawn serve(env, connection, cache)` starts a job with its
own stack. Services (`*.svc`) declare state, a mailbox and one handler per message type; templates (`*.tpl`) become
functions with a build-time maximum size. `bench/web` shows all of it; [design/mailboxes.md](design/mailboxes.md) and
[design/web-app-plan.md](design/web-app-plan.md) explain why.

## Not supported yet

The compiler says "not supported by the self-hosted compiler yet: ..." and names the construct. Verified today: range
types (`int 0..=100`, also as an alias or a field type; the message may say "type arguments" or "refined type forms"),
the `Out` helpers `line`, `int` and `long` (message: "method calls"; use `print(x)` or `env.out.write(bytes)`), and
anonymous functions (use a named top-level function). `print` takes ints, bools, text, enums, structs and collections, and doubles and floats on their own, but
not floats inside a struct or collection. `--runtime=core` has further limits; the default is `--runtime=c`. Known workarounds are in [campfire-friction.md](campfire-friction.md).

## Common mistakes

- `none` as a variable name is refused (it is the empty `Option`).
- Variables cannot shadow other variables, parameters, functions or types in scope.
- `expected int, found never` on a string literal usually means the function's return type is wrong, not the literal.
- The compiler reports **one** error and stops; fix it and run `nlc check` again. `nlc` adds the source line and a caret
  under the column; `nlc check --json <package>` prints each error as a JSON object (file, line, col, severity, message, source).
