# next-lang as a self-hosting language (Claude)

Self-hosting means the compiler is written in the language it compiles: today `nlc` is Rust; a self-hosted `nlc` would be next-lang, built first by the Rust one and then by itself. This is my assessment, written before reading Sol's (docs/reviews/sol-selfhost-r1.md) so the two are independent.

## Short answer

Yes, it's a good fit, better than for most new languages, because the design already leans the way fast modern compilers are built (Zig's, Carbon's, the TypeScript Go port): syntax trees as arrays indexed by ids, text as offsets into one buffer, files parsed in parallel and then read by many threads. Several of next-lang's restrictions are exactly the discipline those compilers adopt by choice. But it's not ready: about six features a compiler needs aren't designed yet, and doing it before M4 would mean writing a compiler in a language that keeps changing under it. A self-hosted compiler is best as **the fourth validation program** (the parallel tool in DESIGN.md's Validation plan), started once M3 is solid, beginning with the lexer and parser.

## How a compiler maps onto the design

| Compiler part | In next-lang | Fit |
| --- | --- | --- |
| Source files | `Bytes` read once per file, bounded by a declared maximum file size | good |
| Tokens | a `list<Token, N>` per file, `Token { kind, start: long, len: int }`, text as offsets into the file, no copying | good: this is how fast lexers work anyway |
| Syntax tree | a frozen pool per file (a builder while parsing, then `freeze`), nodes linking by typed ids, children as id ranges; one `batch` for the whole program | very good: it's the "Frozen pools" section's motivating case |
| Parsing | recursive descent needs recursion, so the parser's functions are marked `recursive`, with the native-stack byte budget; or a precedence-climbing loop with an explicit stack (a `list` of operators) for expressions | workable; deeply nested input hits the budget and fails cleanly with a message, which is acceptable for a compiler |
| Names and interning | a `map<Ascii max 255, SymbolId, N>` per job, plus a merge step after parallel parsing; or a writer-owned shared interner | the one awkward spot: a shared interner written by many threads is "off the table" by design, so it's per-thread tables merged, or a writer |
| Scopes and symbols | a pool of scopes and a pool of symbols, scopes linked by parent id | good |
| Types | a pool of type descriptions, with types compared by id after interning | good |
| Checking | per-function jobs reading the frozen trees in parallel, each with its own result tables (the TypeScript Go port's design) | very good |
| Diagnostics | a bounded `list<Diagnostic, 1000>` per job; past it, "too many errors" | fine; compilers cap errors anyway |
| Code generation | append LLVM IR text to a growing `Text` (or `Bytes`) builder per function, then write the file | fine once M3's growing values exist; needs a large bound (`Bytes max 256 MB`) |
| Running clang | the `spawn` effect with a process capability, capturing output | needs designing (below) |
| Tests | `test` blocks and `check fast == reference` comparing the self-hosted output with the Rust compiler's | very good |

## What fights the rules, honestly

- **Everything needs a bound, and a compiler's input sizes vary.** The practical answer is to declare limits from the input, which DESIGN.md already allows for builders ("derives them from its input only through a formula the parser proves"): a file of at most 4 MB has at most 4 million tokens and, say, 4 million nodes. Program-wide limits go in the compiler's manifest (most files, most functions) and are generous. A compiler that says "this file is over 4 MB" is unusual but not unreasonable; most real compilers have such limits somewhere, just undocumented.
- **No closures** makes visitor-style tree walks a little more verbose: a walk is a `match` on the node kind in a loop or a `recursive` function, passing a context explicitly. That's how many compilers written in C or Zig look, and it reads fine.
- **No implicit conversions** costs the most in a compiler, which juggles offsets (`long`), lengths (`int`) and indexes constantly; the widening methods help. Expect `.to_long()` often.
- **Recursion only by opt-in** is fine: marking the parser, the type checker's walk and the printer `recursive` is honest about where the stack can grow.

## What's missing from DESIGN.md for a compiler

1. **Traits or interfaces for generic code** (open now): a compiler wants a few generic containers (a `map` keyed by any interned id, a sort with a comparison). Decide before M5.
2. **Process spawning:** run clang, capture its output and exit code, as a capability with a declared output bound. Belongs with Effects (M5-ish).
3. **File system beyond reading:** listing a directory (used in the examples, not designed), writing output files, temporary directories.
4. **Formatting text:** building error messages and IR needs number formatting, padding, and escaping into a builder; a small `format` family in the standard library.
5. **Sorting and hashing** in the standard library, with bounded inputs.
6. **A large-output story:** writing hundreds of megabytes of IR as it's produced (streaming to a file in chunks) rather than holding all of it, so the bound doesn't have to be the whole output.

## Bootstrapping

1. **Stage 0:** the Rust `nlc` (what exists now) compiles the next-lang compiler's source to **stage 1**.
2. **Stage 1** compiles the same source to **stage 2**; stage 2 compiles it to **stage 3**.
3. **Correctness check:** stage 2 and stage 3 must be identical, byte for byte (the compiler's output doesn't depend on which build of the compiler made it). That requires deterministic output: no hash-order iteration, no timestamps, stable naming, which DESIGN.md already wants for replays.
4. **Agreement check:** for every program in `tests/`, the Rust compiler's output and the self-hosted one's must behave the same, a `check fast == reference` across the whole test suite.
5. Keep the Rust compiler as the reference until the self-hosted one passes everything, then freeze the Rust one at a tagged version that can always rebuild stage 1.

## Recommendation

- **Not now.** M0 to M3 change the language's core every week; a compiler written in it would be rewritten repeatedly.
- **Start after M3** (data stacks and growing values work), with the **lexer and parser only**, as the parallel tool program in the validation plan: parse every test package in parallel into frozen pools, and compare the trees with the Rust parser's. That exercises frozen pools, builders, parallel loops and bounds on a real workload, which the design needs proved anyway.
- **Then the checker, then code generation,** each checked against the Rust compiler's output.
- **Risks:** the design's untested parts (frozen pools, parallel loops, data stacks under heavy text building) all land on the compiler at once; a performance problem in any of them shows up as a slow compiler. That's also the benefit: it's the most demanding real program the language will see early, and it's one the team understands completely.
