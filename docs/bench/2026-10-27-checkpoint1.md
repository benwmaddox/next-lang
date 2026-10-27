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

36 of 41 ports correct at the full `run` size; the 5 others wait for floats (csv_parse, distance_jaro, distance_ngram, json_parsedom, json_parsemapping). Run times 0.17 s (json_generate) to 4.04 s (etc_logparser). No Rust comparison in this runner yet.

## What the self-hosted compiler needs for Osprey and LangArena

After renaming the ports' locals that reused built-in names (9805988), the first blocker for the 64 programs it can't build is: `const` (35, E3e), recursion or generics (12, E4s), `type` aliases (10, E4, or `byte` from E3c), float literals (4, F1), other (3). Behind those: command-line arguments and stdin (48 programs, E3f1), text values (31, E3c-E3d1), growable lists (30, E3d2), sort (5, E4s), maps (9, E4). Most should build around B1; maps after E4, floats after F1.

## Next checkpoint

1b, after P1 (post-B1). Before then, the self-hosted slowdown on lists and `write` parameters gets its own look (above).
