# O1: offset runtime and inline stack allocation

## Implemented

- Added `NLC_STACK_MODE=pointer|offset`; pointer mode remains the default. Offset mode uses a movable, mmap-backed data stack with a 256 KiB initial reservation, a guard page, doubling growth via `mremap`, optional preallocation and growth statistics, and `NLC_STACK_VERIFY=1` poisoning of old mappings.
- Ported the supported offset slice onto the current inline string storage and pointer-free collection lanes. Large list locals, scalar-field struct lists, read/write list parameters, result destinations, and local Ascii builders with `try_append`, `str`, and `grow` parameters use offsets across growth. The preflight rejects unsupported storage and operations before LLVM emission with an offset-mode diagnostic.
- Added base and limit caching with reloads after growth-capable calls. Stack-backed Ascii descriptor pointers are tagged offsets and decoded at use sites. List count and lane accesses carry the offset-mode alias scopes.
- Replaced per-allocation runtime calls with inline alignment, overflow and limit checks. `nl_stack_alloc` and `nl_stack_alloc_offset` are in the slow blocks only. Offset slow paths grow and refresh cached base and limit; pointer slow paths retain the exhaustion failure. High-water accounting is updated without a runtime call per allocation. The cached top is published before stack-placing generated calls and at exits; the inline allocation fast path has no context calls.
- Added the two X1 runtime fixtures, four benchmark packages, expected output snapshots, an offset-mode IR test, and a fail-closed map test. No external crates were added.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed under `ulimit -v 8000000` and `timeout 900s`.
- `NLC_STACK_MODE=pointer CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test -q` — passed under `ulimit -v 8000000` and `timeout 900s`, including selfhost parity (318.90 s) and the fixture harnesses.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check` and `git diff --check` — passed.
- `compiler/tests/ascii_values.rs`, `compiler/tests/offset_stack.rs`, and `compiler/tests/stack_contracts.rs` passed. Both offset fixtures matched pointer-mode stdout at O1 and O3 with `NLC_STACK_VERIFY=1`; the slice fixture recorded four relocations, and the cache-call fixture recorded one. The IR tests confirm allocation calls occur only in slow blocks in both modes and the cached top is published before a stack-placing call.
- All four X1 benchmark programs built in pointer and offset modes at O1 and O3. Their stdout matched across the saved pre-O1 pointer binaries, saved X1 offset binaries, and current binaries in both dynamic and preallocated modes.

The final suite run was under `ulimit -v 8000000` and `timeout 900s`. The offset fixtures began with the runtime's 256 KiB reservation, so the verify runs exercised moves and poisoned old mappings.

## Measurements

Measurements are best of five fresh processes, with before and after variants interleaved. Selfhost and T30/T32 before binaries were saved from main before O1. The before offset binaries are the saved X1 spike binaries because main did not yet have an offset mode. RSS is reported for the selfhost measurements; the X1 table focuses on elapsed time and stack counters.

### Selfhost lexer and parser

The lexer and parser comparisons used the 13-file, 54,145-line benchmark corpus. The lexer was timed with the saved before/after selfhost binaries; `scripts/bench-selfhost.sh` was also run after O1 for the parser.

| Workload | Before best | After best | Max RSS |
| --- | ---: | ---: | ---: |
| Lexer | 0.0800 s | 0.0746 s | 14,080 KiB |
| Parser (`--tokens --tree`) | 0.2461 s | 0.2487 s | 58,784 KiB |

`scripts/bench-selfhost.sh` after O1 measured 0.25, 0.25, 0.25, 0.27, and 0.25 seconds; best was 0.25 seconds at 58,608 KiB RSS. The interleaved parser timings are flat within run-to-run variation.

### T30 and T32

| Benchmark | Opt | Before best | After best | Max RSS |
| --- | ---: | ---: | ---: | ---: |
| `bench/t30_locals` | O1 | 0.1097 s | 0.0681 s | 11,440 KiB |
| `bench/t30_locals` | O3 | 0.1117 s | 0.0668 s | 11,440 KiB |
| `bench/t32_number_output` | O1 | 0.9128 s | 0.9126 s | 11,440 KiB |
| `bench/t32_number_output` | O3 | 0.9055 s | 0.9082 s | 11,440 KiB |

### X1 list, call, and builder benchmarks

Elapsed time is in milliseconds. `Offset prealloc` sets `NLC_STACK_PREALLOC=1`; dynamic mode starts at 256 KiB.

| Workload | Opt | Before pointer | After pointer | Before offset dynamic | After offset dynamic | Before offset prealloc | After offset prealloc |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `offset-tight-list` | O1 | 7.810 | 7.798 | 9.915 | 7.834 | 9.803 | 7.822 |
| `offset-tight-list` | O3 | 7.779 | 7.685 | 9.762 | 7.874 | 9.898 | 7.752 |
| `offset-struct-list` | O1 | 7.935 | 7.815 | 9.962 | 7.817 | 9.875 | 7.757 |
| `offset-struct-list` | O3 | 7.709 | 7.833 | 10.043 | 7.855 | 9.808 | 7.853 |
| `offset-calls` | O1 | 1.959 | 1.889 | 3.915 | 2.041 | 3.826 | 2.022 |
| `offset-calls` | O3 | 1.555 | 1.581 | 3.700 | 1.637 | 3.649 | 1.664 |
| `offset-builder` | O1 | 19.335 | 19.250 | 52.742 | 19.017 | 52.633 | 19.069 |
| `offset-builder` | O3 | 19.230 | 18.910 | 35.486 | 19.659 | 36.060 | 19.460 |

Current dynamic runs grew once and relocated once for each workload; preallocated runs had zero growths and relocations. Their reservations and high-water marks were:

| Workload | Preallocated reservation | Dynamic reservation | Peak used | Dynamic `mremap` time across runs |
| --- | ---: | ---: | ---: | ---: |
| `offset-tight-list` | 307,200 B | 524,288 B | 305,552 B | 4,662–5,912 ns |
| `offset-struct-list` | 294,912 B | 524,288 B | 291,088 B | 4,579–6,441 ns |
| `offset-calls` | 372,736 B | 524,288 B | 371,096 B | 5,217–7,745 ns |
| `offset-builder` | 24,002,560 B | 33,554,432 B | 24,000,008 B | 4,884–9,256 ns |

The pointer timings were stable before and after. The final offset list loops and builder were close to pointer time in this environment; the saved X1 binaries were slower in the same interleaved run. The call case is short enough that individual-run noise is visible.

## Parser profile

Recorded the final selfhost parser with WSL `perf` 6.8.12 using a 997 Hz sampling frequency and DWARF call graphs. The profile captured 208 samples with no lost samples. The largest reported symbols were `__memmove_avx_unaligned_erms` (10.10%), `nl_context_set_top` (9.13%), `nl_fn_1` (7.21%), `nl_fn_49` (6.73%) and `nl_ascii_format_i64_decimal` (5.77%). The `nl_context_set_top` samples are the required writebacks before calls with stack requirements and reflect the remaining call-boundary cost. Raw data was written to `/tmp/o1-final/perf.data`.

## Notes

The before offset measurements use the read-only X1 worktree's already-built binaries and saved results; I did not modify that worktree. Offset support remains deliberately limited and fails closed outside the tested slice. The T30 speedup is consistent with removing a runtime allocation call from each stack-region allocation; T32 number output remains within measurement noise. This compiler stage has no may-suspend call classification, so the writeback sites cover stack-placing generated calls; future suspension effects will need their own call-site classification.
