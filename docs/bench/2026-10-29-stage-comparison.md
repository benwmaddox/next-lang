# Compiler stage comparison, 2026-10-29

Runtime of benchmark programs compiled by each compiler stage, full-size parameters, 5 timed samples plus one validated warmup per case, whole-process median seconds (LangArena times include preparation and its own warmup). Every sample's stdout was checked byte for byte before timing. Each process was pinned to CPU 8 under `/home/ben/linuxbench/bench.lock`. Runner: `bench/compare-compiler-runtimes.py` (see `bench/compare-compiler-runtimes.md`).

- Stage 0: Rust compiler, pointer data stack. Stages 1-3: self-hosted compiler built by stage 0 (1), stage 1 (2), stage 2 (3); offset data stack. All IR is linked with the same `clang -O3` and `runtime/nl_runtime.c`.
- Stage 1 is a build of the working tree that includes int-constant support (not part of this PR); stage 2 and 3 are byte-identical (`.selfhost-stage-chain-takeover1029`).
- 35 of 86 cases build on all four stages. The other 51 are skipped for stages 1-3 because the self-hosted compiler rejects a feature (below), or are pending floats. No case produced wrong output.

## Runtime (35 cases on all four stages)

| Case | Stage 0 | Stage 1 | Stage 2 | Stage 3 |
|---|---:|---:|---:|---:|
|langarena/binarytrees_arena | 0.471679 s | 0.468114 s (0.992×) | 0.466570 s (0.989×) | 0.489974 s (1.039×) |
|langarena/clbg_fannkuchredux | 0.894399 s | 0.912443 s (1.020×) | 0.960513 s (1.074×) | 0.887580 s (0.992×) |
|langarena/etc_gameoflife_idiomatic | 0.671131 s | 0.945214 s (1.408×) | 0.956027 s (1.425×) | 0.958779 s (1.429×) |
|langarena/etc_sieve | 1.844257 s | 2.470757 s (1.340×) | 2.457137 s (1.332×) | 2.476117 s (1.343×) |
|langarena/graph_astar | 0.872630 s | 1.267047 s (1.452×) | 1.289629 s (1.478×) | 1.223729 s (1.402×) |
|langarena/maze_generator_idiomatic | 0.780103 s | 0.773470 s (0.991×) | 0.779806 s (1.000×) | 0.777758 s (0.997×) |
|langarena/sort_merge | 1.970757 s | 2.923603 s (1.483×) | 2.783383 s (1.412×) | 2.871719 s (1.457×) |
|langarena/sort_merge_idiomatic | 1.887415 s | 2.744665 s (1.454×) | 2.889819 s (1.531×) | 2.726433 s (1.445×) |
|langarena/sort_quick | 1.518642 s | 1.860800 s (1.225×) | 1.879113 s (1.237×) | 1.953493 s (1.286×) |
|langarena/sort_quick_idiomatic | 1.450525 s | 1.889245 s (1.302×) | 1.893925 s (1.306×) | 1.909670 s (1.317×) |
|osprey/ackermann | 0.311424 s | 0.155913 s (0.501×) | 0.159535 s (0.512×) | 0.155679 s (0.500×) |
|osprey/coins | 0.176690 s | 0.114096 s (0.646×) | 0.115133 s (0.652×) | 0.117985 s (0.668×) |
|osprey/collatz | 0.098828 s | 0.072982 s (0.738×) | 0.073887 s (0.748×) | 0.073323 s (0.742×) |
|osprey/coprime | 0.135327 s | 0.091369 s (0.675×) | 0.087239 s (0.645×) | 0.087777 s (0.649×) |
|osprey/digitsum | 0.045125 s | 0.021313 s (0.472×) | 0.018846 s (0.418×) | 0.017558 s (0.389×) |
|osprey/factorial | 0.036385 s | 0.035588 s (0.978×) | 0.034645 s (0.952×) | 0.035737 s (0.982×) |
|osprey/fib | 0.116951 s | 0.039840 s (0.341×) | 0.043162 s (0.369×) | 0.039948 s (0.342×) |
|osprey/gcdsum | 0.126203 s | 0.087255 s (0.691×) | 0.083891 s (0.665×) | 0.085317 s (0.676×) |
|osprey/hanoi | 0.205840 s | 0.048415 s (0.235×) | 0.047852 s (0.232×) | 0.050613 s (0.246×) |
|osprey/isqrt | 0.030130 s | 0.028772 s (0.955×) | 0.029628 s (0.983×) | 0.027822 s (0.923×) |
|osprey/josephus | 0.041057 s | 0.042455 s (1.034×) | 0.040768 s (0.993×) | 0.043514 s (1.060×) |
|osprey/listops | 0.007768 s | 0.008672 s (1.116×) | 0.006540 s (0.842×) | 0.006991 s (0.900×) |
|osprey/mutual | 0.354451 s | 0.021386 s (0.060×) | 0.022658 s (0.064×) | 0.021823 s (0.062×) |
|osprey/nestedloop | 0.047647 s | 0.047488 s (0.997×) | 0.048507 s (1.018×) | 0.049488 s (1.039×) |
|osprey/pascal | 0.118877 s | 0.044059 s (0.371×) | 0.045179 s (0.380×) | 0.047973 s (0.404×) |
|osprey/powmod | 0.098767 s | 0.029926 s (0.303×) | 0.029558 s (0.299×) | 0.030071 s (0.304×) |
|osprey/primes | 0.070355 s | 0.019346 s (0.275×) | 0.017426 s (0.248×) | 0.017701 s (0.252×) |
|osprey/tak | 0.180261 s | 0.061825 s (0.343×) | 0.061656 s (0.342×) | 0.062407 s (0.346×) |
|vs-rust/calls | 0.891968 s | 0.724893 s (0.813×) | 0.737325 s (0.827×) | 0.770947 s (0.864×) |
|vs-rust/collatz | 0.553841 s | 0.548307 s (0.990×) | 0.559475 s (1.010×) | 0.555123 s (1.002×) |
|vs-rust/increment_heavy | 0.706735 s | 2.324220 s (3.289×) | 2.234534 s (3.162×) | 2.272639 s (3.216×) |
|vs-rust/request_scratch | 0.973379 s | 1.079414 s (1.109×) | 1.061119 s (1.090×) | 1.076480 s (1.106×) |
|vs-rust/struct_math | 0.319868 s | 0.335860 s (1.050×) | 0.337138 s (1.054×) | 0.335282 s (1.048×) |
|vs-rust/struct_update | 0.774869 s | 2.010518 s (2.595×) | 2.086348 s (2.693×) | 2.060273 s (2.659×) |
|vs-rust/tight_list | 0.512253 s | 0.517904 s (1.011×) | 0.504202 s (0.984×) | 0.507074 s (0.990×) |

Ratios are against Stage 0 on the same case (above 1 is slower). Reading them:

- Most compute-bound LangArena cases are within about ±10% on all stages; sort, sieve, A* and game-of-life variants run 1.2-1.5x slower on stages 1-3.
- Small Osprey programs run faster on stages 1-3 (fib 0.34x, hanoi 0.24x, mutual 0.06x). Stage 0 uses the pointer data stack and stages 1-3 the offset data stack, so this is probably the stack mode rather than the compiler; not yet isolated.
- The two real regressions are `vs-rust/increment_heavy` (3.2x) and `vs-rust/struct_update` (2.6x), both `write`-parameter list/struct update loops. They match the earlier E3a3 finding (docs/reviews/sol-selfhost-perf-r1.md) and are not fixed in the self-hosted compiler yet.
- Stage 2 and stage 3 agree within noise on every case, as expected from identical binaries.

## Cases the self-hosted compiler cannot build yet (stage 0 builds all)

First error per case, 138 failed builds across stages 1-3 (46 cases x 3):

| Missing feature | Cases |
|---|---:|
| Type aliases | 16 (compress_* x11, hash_crc32, hash_sha256, etc_logparser, Osprey mergesort, quicksort) |
| Constant declarations (text and array constants) | 9 (base64_*, brainfuck_*, template_*, Osprey textstats, wordfreq) |
| Calls to built-in functions | 6 (etc_words, graph_dfs, maze_astar x2, sort_self, search_heavy); needs review |
| Text in collections | 4 (calculator_ast, calculator_interpreter, etc_cachesimulation, tokenize) |
| `queue` type | 3 (graph_bfs, maze_bfs x2) |
| Struct declarations (one form) | 3 (binarytrees_obj, Osprey binarytrees, exprtree) |
| Nested collections | 3 (etc_gameoflife, maze_generator, nested_lists) |
| Stricter checks than stage 0 | 2 (json_generate needs a `(byte)` cast; text_format cannot prove an append fits `Ascii max 7000000`) |
| Floats (declared pending) | 5 (csv_parse, distance_jaro, distance_ngram, json_parsedom, json_parsemapping) |

## Build time per phase

Single runs on 2026-10-29, pinned to cores 14-21, nothing else running. Stage 1 is stage 0 building the self-hosted compiler; stage 2 is stage 1 building it again; stage 3 is stage 2 doing so. Stage 2 and 3 are LLVM IR emitted by the previous stage, linked by `clang -O<level>` with `-DNLC_STACK_MODE_OFFSET=1`. `nlc` accepts only `NLC_OPT_LEVEL` 1 or 3, so the "-O0" stage 1 is built at level 1.

| Phase | -O0 (stage 1: level 1) | -O3 |
|---|---:|---:|
| Stage 0: clean `cargo build --bin nlc` (debug / release) | 8.1 s | 15.0 s |
| Stage 1: Rust `nlc` builds the self-hosted compiler | 36.1 s | 46.3 s |
| Stage 2: stage 1 emits IR / clang | 1.2 s / 4.0 s | 1.4 s / 16.6 s |
| Stage 3: stage 2 emits IR / clang | 33.4 s / 3.6 s | 1.3 s / 18.7 s |

Stage 2 and 3 binaries are identical at both levels. The 33.4 s at -O0 stage 3 is the unoptimized stage 2 binary emitting IR; an -O3 compiler emits it in about 1.3 s, so the time lost compiling the compiler at -O0 is paid back many times over.

## Method notes and caveats

- Exact commands, hashes and every sample are in the runner's `report.json` (not committed; about 40 MB with logs). Regenerate with the command in `bench/compare-compiler-runtimes.md`.
- The Rust-vs-next-lang reference column was not run here.
- A full-suite correctness pass (`--mode test`) produced no output mismatches on any stage.
