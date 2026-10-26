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

## Second run: all pairs, three ways (same day, 16:15)

Added: the allocation pairs (Rust's standard heap approach, a fresh `Vec`/`String` per value, against next-lang's bump allocation on the data stack with scope reset; each with a buffer-reusing Rust version, "reuse"), two pairs the self-hosted compiler can already build (`collatz`, `struct_math`: scalars, structs and calls only), and the self-hosted compiler (built from HEAD 6f5da36, programs linked at O3 with its core library, no libc). Same conditions as above (`scripts/bench-vs-rust.sh --selfhost --time`; `text_format` rerun after scaling it to about 1 s). Ratios above 1 mean next-lang is slower.

| Pair | stage 0 | self-hosted | Rust | Rust reuse | stage 0 / Rust | self-hosted / Rust | stage 0 / reuse |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| collatz | 0.60 s | 0.61 s | 0.36 s | | 1.67 | 1.69 | |
| struct_math | 0.35 s | 0.33 s | 0.31 s | | 1.13 | 1.06 | |
| increment_heavy | 0.73 s | | 0.58 s | | 1.26 | | |
| struct_update | 0.89 s | | 0.53 s | | 1.68 | | |
| tight_list | 0.56 s | | 0.26 s | | 2.15 | | |
| calls | 0.97 s | | 0.19 s | | 5.11 | | |
| search_heavy | 0.53 s | | 0.05 s | | 10.6 | | |
| nested_lists | 0.88 s | | 1.34 s | 0.90 s | **0.66** | | 0.98 |
| request_scratch | 1.04 s | | 1.12 s | 1.06 s | **0.93** | | 0.98 |
| tokenize | 0.85 s | | 0.92 s | 0.91 s | **0.92** | | 0.93 |
| text_format | 0.96 s | | 2.47 s | 1.69 s | **0.39** | | 0.57 |

Peak RSS was 1.6-3.3 MB for every program in both languages (next-lang equal or lower). Binaries: stage 0 about 97 KB, self-hosted 19 KB (core library, no libc), Rust about 308 KB, all stripped or static.

- **Allocation-heavy work favours next-lang already, even through stage 0:** 2.6x faster than idiomatic Rust on text formatting, 1.5x on nested lists, 5-8% on per-request scratch and tokenising. Against Rust that reuses its buffers, next-lang is still faster on text (1.8x) and level elsewhere: the gain is the allocator plus in-place builders, and careful Rust can recover most of the allocator part by hand.
- **Compute-heavy loops favour Rust** (1.1x to 10x): the overhead items now in PLAN as P1 (overflow and bounds checks, inlining, inline search and sort).
- **The self-hosted compiler matches stage 0** on the two pairs it can build (1.69 against 1.67, 1.06 against 1.13): same LLVM, no regression from offsets or the core library, with binaries a fifth the size. Its own approaches (offsets on a moving stack, inline bump allocation) only start to show once it has regions and collections (E3a1, E3a2), at checkpoint 1.
