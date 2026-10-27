# S3: full test suite speed

## Measured result

Measurements used the `s3-suite-speed` worktree at existing HEAD `5a0d76a` (the local `main` ref also resolved there; the task note cites `7e3fea0`). I left refs and history unchanged. Runs used the release profile, the bench lock at `/home/ben/linuxbench/bench.lock`, `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target-s3`, and `ulimit -v 8000000`. Worker default was 11 (`NLC_TEST_JOBS` unset) on the 22-logical-CPU, 31 GB machine. All measurements were on the same workspace; no test packages were changed.

| Suite | Baseline summed test-binary time | After summed test-binary time |
| --- | ---: | ---: |
| `NLC_FRONTEND=rust` | 1,102.325 s (18m 22s) | 446.400 s (7m 26s) |
| `NLC_FRONTEND=selfhost` | 1,184.870 s (19m 45s) | 195.568 s (3m 16s) |
| **Both** | **2,287.195 s (38m 07s)** | **641.968 s (10m 42s)** |

The baseline target timings for the first Rust suite and the first 20 selfhost-suite targets are from `/home/ben/luna-S3-run1.log` (retained in `/tmp/s3-before-times.txt`). That run stopped before the selfhost suite's remaining targets; those missing entries came from the saved baseline completion capture (`/tmp/s3-selfhost-baseline-missing.txt`). The baseline aggregate above is the sum of those per-target measurements, not a single uninterrupted full-suite wall-clock measurement. The after per-target totals are from `/tmp/s3-after-times.txt`.

A separate full-command measurement ran each release suite to completion with the same lock, target directory, and virtual-memory limit:

| Full command | Wall time | Peak process-tree RSS |
| --- | ---: | ---: |
| `NLC_FRONTEND=rust cargo test --offline --release -q` | 490.24 s (8m 10s) | 3,141 MiB |
| `NLC_FRONTEND=selfhost cargo test --offline --release -q` | 230.62 s (3m 51s) | 204 MiB |
| **Combined sequential wall time** | **720.86 s (12m 01s)** | **4,438 MiB peak observed across the run** |

The per-test-binary numbers and full-command numbers measure different boundaries: the former sum individual Cargo test target wall times, while the latter include the complete command wall time. The complete commands finish 7m 59s under the 20-minute limit. Maximum observed single-process virtual size was 6,634 MiB, below the 8,000,000 KiB per-process-tree limit. The parallel build comparison peaked at about 2,267 MiB process-tree RSS; the long O1/O3 relocation matrix peaked at about 1,742 MiB.

## Per-test-binary wall time

Times are seconds. `rust` and `selfhost` columns identify the `NLC_FRONTEND` suite. Baseline selfhost suffix values use only targets absent from the original run log.

| Test binary | Rust before | Rust after | Selfhost before | Selfhost after |
| --- | ---: | ---: | ---: | ---: |
| `next_lang` | 63.216 | 36.245 | 34.348 | 33.061 |
| `nlc` | 0.063 | 0.067 | 0.062 | 0.050 |
| `ascii_values` | 0.065 | 0.070 | 8.060 | 0.135 |
| `capabilities` | 1.059 | 1.072 | 1.098 | 1.049 |
| `checker_performance` | 0.207 | 0.204 | 8.672 | 0.706 |
| `collections_ir` | 0.103 | 0.092 | 8.471 | 0.169 |
| `core_embed` | 0.150 | 0.136 | 0.216 | 0.111 |
| `core_wrapper_audit` | 0.081 | 0.092 | 0.109 | 0.080 |
| `e2_reference` | 2.600 | 2.517 | 2.860 | 0.048 |
| `globals` | 0.527 | 0.524 | 9.123 | 0.613 |
| `inline_text` | 0.519 | 0.506 | 8.684 | 0.544 |
| `input_policy` | 53.181 | 43.004 | 42.754 | 0.053 |
| `language` | 92.330 | 83.369 | 115.793 | 105.467 |
| `link_ir` | 0.988 | 0.852 | 0.909 | 0.917 |
| `locals_locality` | 0.510 | 0.446 | 9.107 | 0.631 |
| `offset_stack` | 2.152 | 1.955 | 39.845 | 2.394 |
| `parse_dump` | 6.682 | 4.914 | 42.129 | 33.204 |
| `pools_ir` | 0.083 | 0.068 | 7.946 | 0.203 |
| `runtime_heap_calls` | 1.384 | 1.350 | 9.509 | 1.404 |
| `runtime_number_format` | 0.699 | 0.649 | 7.804 | 0.809 |
| `selfhost` | 658.250 | 231.151 | 604.637 | 0.055 |
| `selfhost_context_offsets` | 6.532 | 6.223 | 6.038 | 0.062 |
| `selfhost_interfaces` | 0.069 | 0.064 | 0.055 | 0.051 |
| `selfhost_relocation` | 197.487 | 18.034 | 193.202 | 0.107 |
| `stack_contracts` | 9.173 | 8.907 | 10.237 | 8.951 |
| `stack_reuse` | 0.464 | 0.456 | 0.550 | 0.527 |
| `stdout_pipe` | 1.838 | 1.847 | 2.502 | 2.457 |
| `t25_prerequisites` | 1.305 | 1.101 | 1.362 | 1.186 |
| `text_bytes` | 0.080 | 0.068 | 8.345 | 0.125 |
| `doc` | 0.529 | 0.417 | 0.443 | 0.398 |

## Changes

- The build comparison, relocation matrix, and lexer/parser comparison now distribute packages over a worker pool. The default is half the logical CPUs; `NLC_TEST_JOBS` overrides it. Workers have separate temporary directories and output files, and reports return in package-table order with the existing totals. Parallel peak memory remained below 2.3 GiB RSS for the build comparison under the measured 8,000,000 KiB process limit.
- The build comparison, relocation check, and lexer/parser comparisons use the same source-hash-cached stage-zero compiler. The cache key covers `selfhost/` and `core/` source/package manifests, the reference `nlc`, target/platform, `NLC_STACK_MODE`, and clang/rustc versions; its artifact is integrity-checked. A test-package-only edit therefore reuses the compiler.
- Checks that pin or explicitly invoke the same frontend now run in only the Rust suite: selfhost comparisons, relocation, input-policy (which invokes both frontends per case), E2 reference, context-offset, and interface checks. Their selfhost-suite test binaries report a skip while ordinary selfhost-frontend tests still run in that suite.
- The normal relocation suite checks every build package at O1. O3 is included with `NLC_LONG_TESTS=1`; the full O1/O3 matrix passed for 90 build packages (137 program runs per level, including 13 relocated packages).
- Focused harness selectors support `--only GLOB`, `--class build`, and `--changed [REV]` (default `HEAD`). See [testing commands](../testing.md).

## Verification

Both complete release `cargo test` commands passed. The full build comparison passed with 624 classified packages plus 16 seeded cases: O1 counts were 90 build, 115 diagnose, 45 rejects, and 374 unsupported; there were zero mismatches. Its IR-bound and enum-scaling checks passed. The relocation check passed at O1 in the default suite and at both O1 and O3 with `NLC_LONG_TESTS=1`.

A deliberate lexer mismatch was injected into a temporary selfhost wrapper. The comparison failed as expected and displayed the first output diff (`+intentional mismatch`) and first differing byte; the injected change and wrapper were then removed. The final workspace contains no test-package edits.
