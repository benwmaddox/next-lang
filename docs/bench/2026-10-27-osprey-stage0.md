# Osprey suite, stage 0, 2026-10-27

First run of the 24 Osprey benchmark cases (bench/osprey/, from https://www.ospreylang.dev/benchmarks/, MIT) ported to next-lang. All 24 match Osprey's `expected.txt` exactly. next-lang built by stage 0 at NLC_OPT_LEVEL=3 (C runtime, baseline x86-64); Rust built as Osprey builds it, `rustc -C opt-level=3 -C overflow-checks=off`. Best of 5 wall time (perf_counter around the pinned process), peak RSS. Taken while other agents and a compiler run were active, so small differences are noise; several cases run under 10 ms and say little.

| case | next-lang s | Rust s | ratio | next-lang KB | Rust KB |
|---|---:|---:|---:|---:|---:|
| ackermann | 0.303 | 0.142 | 2.14x | 1936 | 2112 |
| binarytrees | 0.402 | 0.413 | 0.97x | 2288 | 2992 |
| coins | 0.172 | 0.097 | 1.77x | 1584 | 1936 |
| collatz | 0.090 | 0.014 | 6.44x | 1584 | 1936 |
| coprime | 0.128 | 0.074 | 1.72x | 1584 | 1936 |
| digitsum | 0.032 | 0.007 | 4.35x | 1584 | 1936 |
| exprtree | 0.007 | 0.007 | 1.07x | 2816 | 2992 |
| factorial | 0.029 | 0.029 | 1.00x | 1584 | 1936 |
| fib | 0.105 | 0.023 | 4.54x | 1584 | 1936 |
| gcdsum | 0.111 | 0.078 | 1.43x | 1584 | 1936 |
| hanoi | 0.200 | 0.036 | 5.58x | 1584 | 1936 |
| isqrt | 0.022 | 0.017 | 1.32x | 1584 | 1936 |
| josephus | 0.034 | 0.034 | 0.99x | 1584 | 1936 |
| listops | 0.001 | 0.001 | 0.99x | 1584 | 1936 |
| mergesort | 0.002 | 0.003 | 0.82x | 1760 | 2112 |
| mutual | 0.313 | 0.009 | 35.03x | 1584 | 1936 |
| nestedloop | 0.042 | 0.041 | 1.03x | 1584 | 1936 |
| pascal | 0.108 | 0.026 | 4.17x | 1584 | 1936 |
| powmod | 0.085 | 0.022 | 3.83x | 1584 | 1936 |
| primes | 0.059 | 0.011 | 5.52x | 1584 | 1936 |
| quicksort | 0.002 | 0.003 | 0.80x | 1760 | 2112 |
| tak | 0.151 | 0.039 | 3.92x | 1584 | 1936 |
| textstats | 0.006 | 0.002 | 2.61x | 1584 | 1936 |
| wordfreq | 0.005 | 0.004 | 1.21x | 1584 | 1936 |

- **Level or ahead:** binarytrees (pool + stack against Rust's Box), the sorts, josephus, factorial, nestedloop, listops, exprtree; peak memory is lower in every case.
- **Recursive calls are the new weak spot:** fib 4.5x, hanoi 5.6x, tak 3.9x, ackermann 2.1x. Stage 0's `recursive` functions check a recursion budget and pass the job context on every call, and LLVM transforms the plain Rust recursion more freely. `mutual` (35x) is mostly Rust's optimiser turning the mutual recursion into an even/odd test; next-lang makes all ~65M calls (about 5 ns each).
- **Arithmetic loops** (collatz, primes, digitsum, pascal, powmod): the always-on overflow checks again (P1).
- Porting friction worth design attention: no `while` (bounded `for` + `break`), `L` suffixes on every long literal, unwrapping each `push`, no stdin (seeds passed as an argument), no `Ascii.contains`/`starts_with`, no argument parsing helpers.
