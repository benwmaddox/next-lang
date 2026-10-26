**Verdict:** next-lang is easier to read than to write. A newcomer can follow its ordinary algorithms after modest instruction; producing a useful bounded, fallible program currently requires considerably more instruction than the familiar syntax suggests. The central memory design is intelligible, but its obligations spread through everyday signatures and operations. I would keep that design and first improve the teaching surface and repair guidance, then reconsider a few expensive restrictions.

Sol · 2026-10-26. Based on DESIGN, EXAMPLES, accepted fixtures across `tests/run`, `tests/test`, and `tests/e1`, samples throughout `selfhost/*.nl` and `core/*.nl`, and checker diagnostics. Negative fixtures establish rejected forms, not accepted syntax. This is source review, without builds or a measured human/model learning experiment. DESIGN and EXAMPLES explicitly contain proposals; the self-hosted compiler also accepts a smaller subset than the Rust compiler.

## 1. Readability

The basic vocabulary works: `fn`, `struct`, `enum`, `if`, `for`, `let`, `var`, and named fields make intent visible. This complete helper needs almost no explanation:

```nl
fn line(i: int 0..=499) -> Ascii max 80 {
    let name = label(i)
    name + ": " + str(i * 7)
}
```

(`tests/run/t15_append_growth/main.nl:5`.) The refinement and maximum communicate useful contracts. Likewise, `let selected = if true { 4 } else if false { 5 } else { 6 }` is readable despite unfamiliar expression blocks (`tests/e1/control_flow/main.nl:24`).

Understanding mutation requires looking beyond the statement. `for cell in cell_list { cell.value += 1L }` updates the collection, although the loop variable has no mutation marker (`tests/run/t06_core/main.nl:109`). Conversely, `var copied = rocks.get(second).unwrap()` produces a copy whose mutation leaves the pool unchanged (`tests/run/t07_core/main.nl:53`). A reader needs the distinction between iteration views and extracted values.

Defaults hide work: `Core {}` fills omitted fields, including nested defaults; defaults can call functions, and explicit fields suppress their defaults (`tests/run/t04_core/main.nl:14`, `:34`, `:47`). Plain assignment may also wrap or clamp according to a distant type declaration (`:2`, `:37`). Checked arithmetic, job failure, implicit read parameters, and inferred effects are consequential defaults, not merely implementation details. Core's `sys.Addr` operations are privileged runtime machinery, not evidence that ordinary programs have pointers.

## 2. Writability and recovery

A writer must learn these rules explicitly:

- **Bounds:** collection capacity is a constant and part of its type; stored text needs maxima. Empty `list {}` needs context. A helper's conservative output maximum can determine whether its caller compiles, even when actual output is short.
- **Refinements:** ordinary stores require proof; `(Size)(x)` requests a runtime check that can fail the job, while `x.fit<Size>()` returns `Option`. An alias preserves the underlying type; it is not a distinct newtype. Earlier conditions can establish proof (`tests/run/t04_narrowing/main.nl:4`).
- **Modes:** omitted means read. `write` permits mutation; `grow` permits builder length growth. This is type-dependent: `tokens: write list<Token, TOKEN_STORAGE_CAPACITY>` can push (`selfhost/lexer.nl:91`, `:103`), while appending to a `write Ascii` parameter is rejected. Two overlapping arguments cannot be passed when mutation is involved. Calls carry no `&mut`/`ref` marker, so inspect the signature.
- **Failure:** `?` propagates `none` or `err` through a compatible return type; Result errors must match, without Rust's automatic `From` conversion. `??` supplies a lazy fallback or exits control flow, on Option only. `discard` deliberately drops capacity failure from designated built-ins; even a user function returning `Result<_, Full>` is ineligible. `.unwrap()` instead accepts runtime failure. These are different policies, not interchangeable punctuation.
- **Capabilities:** receive `Env`, pass `Fs`/`Out` onward, and grant permissions in `package.toml`. No manifest means `out`; an explicit capability list replaces that default. Adding `capabilities = ["fs"]` therefore disables printing (`tests/run/t20_explicit_capability_replaces_default/package.toml:1`). Package siblings see one another without imports.
- **Text and numbers:** `Ascii` counts bytes, `Text` counts Unicode code points, and `Bytes` holds raw data; code points are not displayed graphemes. `Text max N` normally budgets up to four bytes per point. `let text: Text max 3 = "a😀ß"` demonstrates why `.len()` and `.byte_len()` differ (`tests/run/t16_text_bytes/main.nl:4`). Ascii can feed a read Text parameter, not freely share writable storage. UTF-8/ASCII validation returns Result, whereas `fit` returns Option. Numeric widening still needs spelling; lengths/indexes are `long`, unlike default `int` literals. Narrowing casts check rather than truncate.
- **Loops and identity:** there is no `while`; use bounded `for` plus `break`. Pools supply owner-specific, generation-checked ids, not integers or references; stale lookup returns Option. Learn `nodes.Id`, `Id<nodes>`, and generic owner `P`. Removing during iteration needs a second collection/pass (`tests/run/t07_collect_remove/main.nl:7`). This is substantial knowledge for an ordinary mutable graph.

Option means absence (`some/none`); Result preserves a failure reason (`ok/err`). The compiler usefully diagnoses mixing their match cases, rather than treating them as interchangeable wrappers (`tests/run/t24_option_case/expected.stderr:1`). Named function values are available, but lambdas and capturing closures are not; callbacks need explicit context. Recursion also requires `recursive` and a budget. Those omissions matter when translating a small program from another language.

Some diagnostics really do teach. “collection indexes are long; cast an int index with .to_long()” (`compiler/src/checker.rs:8441`) gives the exact repair. “appending through a parameter requires 'grow' mode; 'write' cannot increase its length” (`:5019`) explains the distinction. Refinement recovery is similarly concrete:

> cannot prove this value fits Small; use (Small)(x) for a checked cast or x.fit<Small>() to handle failure

(`tests/run/t04_unproven_argument/expected.stderr:1`; template at `compiler/src/checker.rs:14213`.) But it omits the inferred interval and why proof failed, and presents a potentially crashing cast without saying so.

Two repair suggestions are misleading. Unused Result guidance says “handle it with '?', 'match', or '??' where supported” (`compiler/src/checker.rs:3904`), yet `:12039` says “'??' works on Option only”. Also, mutating an iteration view of a read parameter reports “cannot assign to immutable 'let' binding 'item'; declare it with 'var'” (`tests/run/t06_read_view_write/expected.stderr:1`); the repair belongs on the collection parameter, not the `for` binding. Diagnostics are promising, but insufficiently reliable to substitute for instruction.

## 3. Consistency, names, punctuation

C# number names are familiar to one audience and conceal widths from another: teach the width table once. More troublesome is combining those names with checked arithmetic, checked casts, and forbidden implicit widening: familiar spelling predicts unfamiliar behavior.

API discovery is uneven: `str(x)` and `abs(x)` are free functions (`selfhost/source.nl:105`; `tests/test/t18_number_text/main.nl:6`), but conversion is `.to_long()`. Arrays use `.len()`, lists commonly `.count()`, and Bytes accepts both (`tests/run/t06_core/main.nl:91`, `:124`; `tests/run/t16_text_bytes/main.nl:14`; `selfhost/parse_output.nl:11`). Text bounds use `max N`, collection bounds use a generic argument. Empty builders use `Bytes.empty()`, collections `list {}`. Each distinction is learnable; together they weaken “one way to write each thing”.

Keep the consistently half-open `..` and inclusive `..=`. The punctuation burden otherwise comes from composition: `ok(input? ?? 0)` is valid (`tests/run/propagation/main.nl:14`) but packs propagation and defaulting into one line. Lowercase `some/none/ok/err`, dot-qualified cases, `=>` match arms, expression tails, and newline/semicolon separation need a compact grammar reference. Keywords `write`, `grow`, and `discard` convey intent better than additional symbols would.

## 4. What bounded memory costs

The best case is compact: `for i in 0..n { out += line(i) }` needs no Full ceremony because the maximum is proved (`tests/run/t15_append_growth/main.nl:12`). Capacities state real product limits and make exhaustion reviewable. The same `push` spelling can require handling or permit omission depending on proof: `for i: long in 0L..3L { exact.push(i) }` fills a fresh capacity-three list without handling (`tests/run/t06_core/main.nl:214`). That is useful but makes acceptance sensitive to surrounding code.

The production evidence is less effortless. A raw scan of the nine selfhost files finds 348 bounded text type mentions, 309 bounded collection type mentions, 177 `.push(` calls, and 164 `.unwrap(` calls; these are occurrences, not independent requirements or measured defects. Startup declares six bounded working buffers together (`selfhost/main.nl:89`), and limits occupy their own file. `buffer.push(source[index]).unwrap()` recurs even in a routine that flushes at 1024 bytes (`selfhost/parse_output.nl:10`).

Full handling can be centralized: `ir_push_byte` sets `compiler.ir_overflow` (`selfhost/compiler.nl:3872`). That helps callers but introduces plumbing and delayed error reporting. Much of the visible cost is repeated type bounds and defensive unwraps, rather than literal `try_append` everywhere. To an algorithm reader this becomes noise; to a resource reviewer it is valuable. Better proofs and reusable buffering helpers can reduce it without abandoning bounds. Tests and compiler internals are not a representative application benchmark, so these counts establish burden, not typical frequency across all domains.

## 5. AI models and a short guide

With no meaningful training corpus, assume models will complete familiar shapes using another language's rules. Rust invites `let mut`, `::`, `Some/Ok`, moves on assignment, automatic error conversion, and treating unused Result as a warning. Swift invites inclusive `...`, optional `T?`, and `&` at mutation call sites. Go invites zero-value assumptions, error tuples, `for condition`, and index-before-value iteration, whereas next-lang uses value-before-index. C# invites implicit widening, unchecked overflow, and nullable rather than Option semantics. Rust's range intuition transfers correctly; Swift's does not.

A short guide must contain: one accepted complete program plus manifest; grammar for declarations, tails, casts, loops and matches; a width/index table identifying implemented numeric types; read/write/grow and copy/view examples; a failure-policy table covering `?`, `??`, `.ok()`, `.unwrap()`, `fit`, and `discard`; capacity/proof recipes; text units/conversions; and a pool lifecycle example. Include one compiler error and repaired version per trap. Name the compiler/subset being targeted. Do not feed models EXAMPLES as an executable specification: its proposed streaming `file.lines(max 4096)` (`docs/EXAMPLES.md:269`) differs markedly from today's buffer-taking I/O (`tests/test/t20_io/main.nl:1`).

## 6. Small programs versus Rust, Go, Zig

My expected learning-cost order for a file-processing tool is Go first; next-lang versus Zig depends on prior systems experience; Rust usually demands more ownership learning. Go postpones memory budgeting and has fewer interacting contracts. Zig exposes allocation and error handling early, but next-lang substitutes capacities, mode distinctions, refinements, and owner ids for explicit allocator work. Rust has a steeper ownership model but much stronger existing teaching material and model familiarity. For fixed-size computation, next-lang can be pleasantly simpler than either systems language; for exploratory text processing, its resource decisions arrive unusually early. These are judgments, not benchmark results.

## 7. Ranked changes

1. **Docs:** Publish a short, compiler-checked “accepted next-lang” guide separate from proposals; writers need an authoritative small target.
2. **Diagnostics:** Remove Result-to-`??` advice and repair view errors at the owner declaration; suggested fixes must work.
3. **Diagnostics:** Show inferred/required ranges or capacities and explain cast failure versus Option recovery; reveal the missing proof instead of merely offering an escape.
4. **Implementation, existing DESIGN:** Extend capacity proofs and provide reusable bounded output helpers; reduce repetitive unwraps while retaining explicit exhaustion policy.
5. **Docs/diagnostics:** Put capability replacement beside the first manifest example and explain lost default grants; adding filesystem access should not mysteriously break printing.
6. **API change, revises DESIGN's surface examples:** Standardize cardinality on `.len()` and document a stable free-function/method convention; reduce memorization and completion errors.
7. **DESIGN change — Ben's no-implicit-conversion decision:** Consider lossless numeric widening, especially int-to-long indexes; ubiquitous mechanical casts buy less clarity than checked narrowing does.
8. **DESIGN change — iteration policy:** Consider a condition loop with an explicit step budget; artificial retry counts such as `for attempt in 0L..1000000L` (`core/format.nl:29`) obscure the actual termination condition.
