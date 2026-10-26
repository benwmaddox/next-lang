# Rough baseline: next-lang (stage 0) against Rust, 2026-10-26

Not a checkpoint: an early look requested by Ben, taken while two compiler sessions were building on other cores (load average about 2 on a 22-thread machine). Each binary was pinned to CPU 8, under the bench lock, best of 5 wall time. Treat differences under about 10% as noise.

- next-lang: stage-0 nlc (Rust nlc at tag stage0 plus E2i), `NLC_OPT_LEVEL=3`, C runtime, baseline x86-64.
- Rust: rustc 1.93.0, `-C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort -C strip=symbols`, baseline x86-64.
- Every pair's output is identical between the two languages (`scripts/bench-vs-rust.sh --time`).

| Pair | next-lang | Rust | next-lang / Rust | Peak RSS next-lang / Rust | Binary next-lang / Rust |
| --- | ---: | ---: | ---: | ---: | ---: |
| calls | 0.94 s | 0.19 s | 4.95x | 1,760 / 1,760 KiB | 96,816 / 307,920 B |
| increment_heavy | 0.74 s | 0.56 s | 1.32x | 1,760 / 1,760 KiB | 96,752 / 307,824 B |
| search_heavy | 0.52 s | 0.05 s | 10.4x | 1,760 / 1,936 KiB | 96,784 / 311,520 B |
| struct_update | 0.86 s | 0.54 s | 1.59x | 1,760 / 1,936 KiB | 96,752 / 307,968 B |
| tight_list | 0.57 s | 0.27 s | 2.11x | 2,288 / 2,464 KiB | 96,752 / 307,968 B |

Memory: equal or slightly lower than Rust. Binaries: about a third of Rust's (stripped, statically linked runtime against Rust's std). Speed: 1.3x to 10x slower.

## Likely causes, to investigate at checkpoint 1 (not yet verified)

- **Overflow checks on every arithmetic operation.** next-lang checks all integer arithmetic; Rust's release builds wrap silently. Checks add branches and block vectorisation: likely most of `calls` (Rust's increments over 1,024 items can become vector code) and part of `tight_list`. Measure with the range facts the checker already has (refinements, loop bounds) emitted as LLVM `range`/`assume` facts, and check whether loop-invariant overflow checks can be hoisted.
- **`binary_search` and `sort_by` as runtime calls.** 10M searches over 10,000 values take 52 ns each in next-lang against 5 ns in Rust, which inlines its generic binary search. Check whether stage 0 calls a C runtime helper per search, and how `Option` results are built.
- **Bounds checks on indexing** that Rust's optimiser removes after inlining; next-lang's checker often knows the index range (`for i in 0..n` over a list of capacity n) and could skip them.
- **Struct-of-arrays layout** in `struct_update` and `increment_heavy` should favour next-lang once the checks above are out of the way.

These are stage-0 numbers. The self-hosted compiler is the line that will be tuned; checkpoint 1 measures it on the first four pairs.
