# Benchmark checkpoint 1, 2026-10-27 (after E3a2)

Checkpoint 1 from PLAN: after E3a2 (arrays, lists, `write` parameters in the self-hosted compiler), at main 24e9805. Same conditions as the [rough baseline](2026-10-26-rough-baseline.md): binaries pinned to CPU 8 under the bench lock, best of 5 wall time, highest optimisation on both sides (next-lang `NLC_OPT_LEVEL=3`; Rust `-C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort`). Every output matched. A Luna run was planning E3b on other cores during the runs (light load); treat differences under about 10% as noise.

## vs-Rust pairs (`scripts/bench-vs-rust.sh --selfhost --time`)

Ratios above 1 mean next-lang is slower. "self" is the self-hosted compiler built from HEAD, programs linked at O3 with its core library (no libc); "-" means it can't build the pair yet.

| Pair | stage 0 | self-hosted | Rust | Rust reuse | stage 0 / Rust | self-hosted / Rust | stage 0 / reuse |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| struct_math | 0.30 s | 0.31 s | 0.27 s | | 1.11 | 1.15 | |
| collatz | 0.53 s | - | 0.32 s | | 1.66 | | |
| calls | 0.83 s | **0.65 s** | 0.17 s | | 4.88 | 3.82 | |
| tight_list | 0.49 s | 0.61 s | 0.23 s | | 2.13 | 2.65 | |
| increment_heavy | 0.73 s | **1.62 s** | 0.50 s | | 1.46 | 3.24 | |
| struct_update | 0.75 s | **1.74 s** | 0.46 s | | 1.63 | 3.78 | |
| search_heavy | 0.50 s | - | 0.05 s | | 10.0 | | |
| nested_lists | 0.79 s | - | 1.28 s | 0.81 s | **0.62** | | 0.98 |
| request_scratch | 0.95 s | - | 1.00 s | 0.95 s | **0.95** | | 1.00 |
| tokenize | 0.74 s | - | 0.81 s | 0.85 s | **0.91** | | 0.87 |
| text_format | 0.82 s | - | 2.12 s | 1.47 s | **0.39** | | 0.56 |

Peak RSS: 1.6-3.3 MB everywhere; the self-hosted builds are equal or lower than stage 0 and Rust (tight_list 1,584 KiB against 2,288 and 2,464). Binaries: self-hosted about 23 KB, stage 0 about 97 KB, Rust about 308 KB (fixed floor, not size per feature).

- **The self-hosted compiler now builds five pairs (was two).** `calls` is 22% faster than stage 0. But the three list and `write`-parameter pairs that E3a2 made buildable are **slower than stage 0**: `increment_heavy` 2.2x, `struct_update` 2.3x, `tight_list` 1.25x. Stage 0 is the bar the self-hosted compiler must reach before P1 tunes past it, so this is the main finding of the checkpoint. Likely suspects, not yet verified: data-stack base reloads after calls that might grow, location-descriptor (offset) arithmetic on every element access, and `write` store-back where stage 0 passes a pointer. An IR comparison of one pair against stage 0 should show which.
- **Stage 0 is unchanged** from the rough baseline (frozen compiler, same machine): allocation-heavy pairs still beat idiomatic Rust (text formatting 2.6x faster, nested lists 1.6x), compute-heavy loops are still 1.1x to 10x slower (P1, after B1).

## Osprey (`bench/osprey/check.py --time`, stage 0)

24 of 24 cases correct. Timings match the [Osprey stage-0 run](2026-10-27-osprey-stage0.md) within noise (fib 4.62x against 4.54x, hanoi 5.58x both times, binarytrees 0.98x against 0.97x), as expected for the frozen compiler. The self-hosted compiler builds 2 of the 24 (isqrt, josephus).

## LangArena (`bench/langarena/check.py --mode run --time`, stage 0)

36 of 41 ports correct at the full `run` size; the 5 others wait for floats (csv_parse, distance_jaro, distance_ngram, json_parsedom, json_parsemapping).

### Against LangArena's Rust, same machine (`bench/langarena/compare-rust.py`)

LangArena's own Rust implementation built here at its `max-perf` profile (opt-level 3, fat LTO, one codegen unit, overflow checks off, `panic = abort`), against the stage-0 ports at `NLC_OPT_LEVEL=3`. One test per process, interleaved, `taskset -c 8`, best of 3, under the bench lock; peak RSS from `/usr/bin/time`. Two Rust times: LangArena's own timer (the measured run only, after a prepare step and a warmup pass) and the whole process (which includes them). next-lang's time is always the whole process, so the first ratio favours Rust and the second favours next-lang; the truth is between.

| Test | next-lang s | Rust s (own timer) | Rust s (process) | next-lang / Rust | next-lang MB | Rust MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| template_regex* | 0.91 | 2.68 | 3.29 | **0.34** | 22.0 | 39.1 |
| etc_gameoflife | 0.65 | 1.59 | 1.93 | **0.41** | 1.9 | 45.2 |
| compress_lzwencode | 0.22 | 0.42 | 0.52 | **0.52** | 2.1 | 4.3 |
| binarytrees_obj | 1.24 | 1.74 | 2.05 | **0.71** | 67.4 | 67.2 |
| graph_astar | 0.89 | 1.25 | 1.67 | **0.72** | 51.2 | 81.6 |
| compress_lzwdecode | 0.26 | 0.32 | 0.44 | **0.79** | 6.7 | 8.6 |
| json_generate | 0.16 | 0.18 | 0.22 | **0.92** | 5.0 | 12.9 |
| maze_generator | 0.75 | 0.76 | 1.14 | 0.98 | 76.1 | 170.9 |
| etc_cachesimulation | 0.52 | 0.50 | 0.60 | 1.04 | 1.9 | 4.0 |
| clbg_fannkuchredux | 0.90 | 0.86 | 1.03 | 1.05 | 1.5 | 3.4 |
| template_parse | 0.93 | 0.84 | 1.10 | 1.10 | 22.0 | 38.4 |
| etc_words | 0.81 | 0.69 | 0.84 | 1.18 | 4.1 | 4.9 |
| graph_bfs | 0.99 | 0.83 | 1.17 | 1.19 | 51.4 | 78.2 |
| hash_crc32 | 0.92 | 0.76 | 0.93 | 1.21 | 6.0 | 4.3 |
| calculator_interpreter | 0.65 | 0.52 | 0.68 | 1.26 | 23.9 | 50.5 |
| maze_astar | 1.25 | 0.95 | 1.46 | 1.32 | 76.3 | 191.2 |
| brainfuck_recursion | 1.82 | 1.29 | 1.29 | 1.41 | 1.7 | 3.4 |
| sort_quick | 1.38 | 0.98 | 1.19 | 1.41 | 4.5 | 6.2 |
| maze_bfs | 0.90 | 0.63 | 1.04 | 1.42 | 76.1 | 179.7 |
| graph_dfs | 0.99 | 0.69 | 1.00 | 1.43 | 48.0 | 78.4 |
| binarytrees_arena | 0.49 | 0.33 | 0.42 | 1.47 | 25.4 | 27.3 |
| compress_arithencode | 1.27 | 0.84 | 1.02 | 1.51 | 2.2 | 3.4 |
| calculator_ast | 0.68 | 0.45 | 0.55 | 1.52 | 7.9 | 18.2 |
| compress_huffencode | 0.86 | 0.56 | 0.67 | 1.54 | 9.1 | 4.6 |
| compress_arithdecode | 1.82 | 1.17 | 1.41 | 1.56 | 2.6 | 3.6 |
| sort_merge | 1.86 | 1.17 | 1.42 | 1.59 | 6.0 | 7.7 |
| hash_sha256 | 0.98 | 0.61 | 0.75 | 1.61 | 5.7 | 4.3 |
| etc_sieve | 1.76 | 1.05 | 1.27 | 1.67 | 4.3 | 6.2 |
| brainfuck_array | 1.67 | 0.87 | 0.88 | 1.91 | 1.7 | 3.3 |
| compress_huffdecode | 1.29 | 0.58 | 0.71 | 2.21 | 13.1 | 8.5 |
| compress_bwtdecode | 2.80 | 0.82 | 1.70 | 3.42 | 77.7 | 42.2 |
| sort_self | 1.41 | 0.26 | 0.32 | 5.37 | 6.0 | 7.7 |
| compress_bwtencode | 2.59 | 0.29 | 0.35 | 9.04 | 8.6 | 7.1 |
| base64_decode | 1.85 | 0.17 | 0.22 | 10.7 | 2.9 | 4.8 |
| etc_logparser* | 3.75 | 0.24 | 0.30 | 16.0 | 8.2 | 11.6 |
| base64_encode | 3.94 | 0.16 | 0.20 | 24.3 | 2.6 | 4.9 |

\* The next-lang ports of template_regex and etc_logparser use hand-written scanners where Rust uses the `regex` crate, so neither is a like-for-like comparison.

- **Speed:** geometric mean 1.62x slower against Rust's own timer, 1.27x against its whole process. next-lang is faster on 8 of 36 tests by the first measure and 18 of 36 by the second. It wins where Rust allocates per object or per string (game of life, LZW, object trees, A*, JSON output) and loses on byte loops (base64 10-24x, BWT encode 9x, `sort_self` 5x): the overflow and bounds checks that block vectorisation, the P1 items.
- **Memory:** lower in 29 of 36 tests, geometric mean 0.64x of Rust's peak RSS (up to 24x lower on game of life, 2.3x on the mazes). The exceptions are BWT decode (78 against 42 MB), the Huffman pair and the hashes, where next-lang sizes buffers at their full static capacity.
- Published LangArena numbers from their machine (Ryzen 7 3800X) flattered next-lang: Rust here is 1.3-2x faster than their published times, so only same-machine runs count from now on.

## What the self-hosted compiler needs for Osprey and LangArena

After renaming the ports' locals that reused built-in names (9805988), the first blocker for the 64 programs it can't build is: `const` (35, E3e), recursion or generics (12, E4s), `type` aliases (10, E4, or `byte` from E3c), float literals (4, F1), other (3). Behind those: command-line arguments and stdin (48 programs, E3f1), text values (31, E3c-E3d1), growable lists (30, E3d2), sort (5, E4s), maps (9, E4). Most should build around B1; maps after E4, floats after F1.

## Next checkpoint

1b, after P1 (post-B1). Before then, the self-hosted slowdown on lists and `write` parameters gets its own look (above).
