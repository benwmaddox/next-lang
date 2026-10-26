# S2 report: build and suite fixes

## Implemented

- Ordinary package builds request native frame sizes only when the compiled package has recursive functions. `stack_peak` and `inspect stacks` still explicitly request native bounds. A nonrecursive build without such a request uses one clang build and does not emit `.stack_sizes`.
- Measured frame maps are cached under the active target cache at `next-lang-native-frames/`. The key fingerprints the exact LLVM IR, clang flags and version, target, and C runtime source. Writes publish atomically; unreadable or malformed entries are ignored and rebuilt. Recursive fixed-point builds reuse cached measurements while still producing the requested final executable.
- The selfhost build comparison defaults to O1 with the core runtime. `NLC_LONG_TESTS=1` selects O1 and O3 with both core and C runtime legs. Each package's Rust reference is built or run once at O1 and reused across those legs. The test harness's separate main-program reference is also built once and reused.

The starting checkout already had a one-clang-build path for packages with no recursion metadata and no explicit native-bound request. I kept that behavior explicit and added the persistent frame cache for recursive and native-bound paths.

## Chosen scope

- `nlc inspect stacks` requests native bounds. The current `nlc inspect contracts` command reports data-stack contracts only and has no native-bound option, so it does not run frame measurement.
- `nlc link-ir` rejects recursion-check metadata and does not request native bounds. It does not share the frame-size step, so no separate link-ir timing was needed.

## Timings

Build timings are best of five. Every build ran under `ulimit -v 8000000` and `timeout 120s`.

| Workload | Before | After |
| --- | ---: | ---: |
| Hello-world `nlc run` | 0.43 s | 0.39 s |
| 10,000-function `nlc build` | 6.05 s | 5.74 s |
| Recursive `tests/run/t19_recursion` via `nlc run` | 0.92 s | 0.45 s |

The recursive after runs used the warm frame cache. An instrumented clang wrapper confirmed a nonrecursive build makes one clang build without `-fstack-size-section`; a repeated recursive build reuses the cached frame measurements without another frame-section build.

The legacy comparison script ran the full matrix regardless of `NLC_LONG_TESTS`; its measured time was 403.24 s, representing either environment setting before this change. Afterward:

| Comparison mode | Time | Result |
| --- | ---: | --- |
| Default, O1/core | 174.55 s | 35 builds, 42 diagnostics, 405 unsupported; 8 generated builds and 8 generated diagnostics; 0 mismatches |
| Long, O1 and O3 with core and C | 265.04 s | Same counts and 0 mismatches at both optimization levels |

## Full-suite verification

Each command used the configured Cargo target directory, a timeout, and `ulimit -v 8000000`:

| `NLC_FRONTEND` | Default | `NLC_LONG_TESTS=1` |
| --- | ---: | ---: |
| `rust` | Passed, 782.41 s | Passed, 1,039.73 s |
| `selfhost` | Passed, 1,075.16 s | Passed, 1,167.21 s |

`cargo build` and the new native-frame cache tests passed. T17/T19 stack-bound, recursion, and fixture checks passed in all four full suite runs.

`cargo fmt --all -- --check` was also attempted. It reports existing formatting differences in untouched compiler and integration-test files, as well as older lines in `driver.rs`; I left those unrelated changes out of this task.

## Remaining

No acceptance work remains for S2. No external crates were added.
