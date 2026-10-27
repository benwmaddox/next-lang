# E2c report: Option, Result, propagation and core wrappers

## Delivered

The self-hosted checker now interns and lays out `Option<T>` and
`Result<T, E>`, including instances inferred from constructors and synthesized
by `.ok()`. It checks `some`, `none`, `ok` and `err`; the supported methods are
`.is_some()`, `.is_none()`, `.is_ok()`, `.is_err()`, `.ok()` and `.unwrap()`.
Option and Result values use the shared sum layout and helper emitters for
copying, equality, printing and matching, including nested sums and unit
payloads.

`?` propagates an Option's `none` or a Result's error through the enclosing
return type. `??` accepts Option and evaluates its fallback only on `none`;
`?? return`, `?? break` and `?? continue` use E2i's `lower_scope_exit`
interface. Result values that are discarded receive a checker diagnostic.
The binding spec's exclusions remain in force, including Result-returning
`main`, optional chaining, and `??` on Result.

Core now defines `Errno { number: int }` and fallible Result wrappers for the
raw syscalls below. The callers in `context.nl`, `environment.nl`,
`format.nl`, `output.nl` and `start.nl` use those wrappers. `write` preserves
the existing `nl_core_sys_write` fault-injection seam.

| Wrapper | Raw operation | Result value |
| --- | --- | --- |
| `write` | `nl_core_sys_write` | bytes written or `Errno` |
| `map` | `sys.map` | mapped address or `Errno` |
| `protect` | `sys.protect` | syscall result or `Errno` |
| `ioctl` | `sys.ioctl` | syscall result or `Errno` |
| `statx` | `sys.statx` | syscall result or `Errno` |
| `sigaction` | `sys.sigaction` | syscall result or `Errno` |
| `openat` | `sys.openat` | file descriptor or `Errno` |
| `close` | `sys.close` | syscall result or `Errno` |

Each wrapper checks `sys.is_error` and converts the negative raw errno to a
positive `Errno.number`. The new `core_wrapper_audit` test walks core sources
and verifies raw fallible calls stay inside wrappers, with one raw-result check
per wrapper. `scripts/embed-core.sh` regenerated `selfhost/core_files.nl` from
9 core files (31,964 source bytes; SHA-256
`763d44d8dfd4b80282092b51547eef8449dd03be2eeaadd95e4830d8302610d2`). No new
C runtime hooks were necessary: the existing printing and expectation hooks
cover the new sum values.

The compiler changes are confined to `selfhost/compiler.nl` and its build
entry in `selfhost/main.nl`. The E2i ownership table remains unchanged. No
mutable globals were added, and no `compiler/src` Stage 0 implementation code
was changed. The only file added under `compiler/` is the required audit test.

## Stage 0 probes

The manager's rule was applied: Stage 0 decides valid-program behavior, while
rejections need only have real error text. These small packages were run with
`nlc run` before pinning the behavior in fixtures.

| Probe | Stage 0 result |
| --- | --- |
| Print nested `Option<Result<Result<...>>>` values | Prints the complete nesting, e.g. `some(ok(err(Bad)))`. |
| Call `.ok()` on a `Result<T, E>` | The return type is `Option<T>`; nesting an Option around a successful Result prints `some(some(ok(7)))`, and an error converts to `none`. |
| Print `some(7)` without an annotation | Accepted and prints `some(7)`. `none` needs an expected Option type; an unconstrained `ok`/`err` needs a Result type. |
| Use `Option.some(7)` as an expression | Rejected as an unknown enum constructor. Qualified Option/Result forms are supported in patterns. |
| Match qualified Result cases | The probe returned the expected `7`, `-2` and `9` from its `ok` and `err` arms. |
| Coalesce an aggregate Option with a lazy fallback | Prints `Pair { value: 3 }`, then `99`, then `Pair { value: 4 }`; the fallback runs only for `none`. |
| Coalesce a Result | Rejected at `main.nl:3:11` with Stage 0's message that `??` works on Option only. The `tests/run/result_coalesce` fixture pins this rejection. |

The new `tests/e2/sum_values` and `tests/e2/coalesce_aggregate` expected output
files were checked against Stage 0. Their outputs are, respectively:

```text
none
some(7)
true
true
err(Bad)
ok(9)
true
true
none
some(9)
9
some(err(Bad))
true
true
9
some(())
none
ok(())
err(())
```

```text
Pair { value: 3 }
99
Pair { value: 4 }
```

The existing propagation fixture also builds and matches Stage 0 for Option and
Result `?`, lazy `??`, and the `return`/`break`/`continue` exits. No Stage 0
reference fix was required. `tests/run/result_coalesce` was changed from an
Ascii fallback to an integer fallback so it isolates Result coalescing, which
is in E2c while user strings remain E3. Its expected rejection text is
unchanged; its parse snapshot was regenerated for the new source.

## Classification

Counts in `tests/e1/classification.tsv` before and after E2c:

| Class | Before | After |
| --- | ---: | ---: |
| `build` | 52 | 59 |
| `diagnose` | 85 | 109 |
| `unsupported` | 410 | 381 |

Moved `unsupported -> build`:

- `tests/run/propagation`
- `tests/run/unwrap_err_failure`
- `tests/run/unwrap_failure`
- `tests/test/enums`
- `tests/test/t04_struct_expect`

Moved `unsupported -> diagnose`:

- `tests/e1/unsupported_op_qq_test`
- `tests/e1/unsupported_op_qq_unreachable`
- `tests/e1/unsupported_op_qq_unused`
- `tests/e1/unsupported_type_option_test`
- `tests/e1/unsupported_type_option_unreachable`
- `tests/e1/unsupported_type_option_unused`
- `tests/e1/unsupported_type_result_test`
- `tests/e1/unsupported_type_result_unreachable`
- `tests/e1/unsupported_type_result_unused`
- `tests/e2/reference_default_try`
- `tests/run/coalesce_exit_outside`
- `tests/run/err_inference`
- `tests/run/none_inference`
- `tests/run/option_question_wrong_return`
- `tests/run/question_error_type`
- `tests/run/question_in_test`
- `tests/run/recursive_enum`
- `tests/run/result_coalesce`
- `tests/run/return_in_test_expression`
- `tests/run/t04_recursive_struct`
- `tests/run/t20_unhandled_result`
- `tests/run/t20_unhandled_result_block`
- `tests/run/t24_option_case`
- `tests/run/t24_result_case`

Two new E2c rows were added together at the end of the classification file:
`tests/e2/sum_values` and `tests/e2/coalesce_aggregate`, both `build`. No
existing expected runtime output or diagnostic oracle changed. The new
fixtures add expected output; the `result_coalesce` parser snapshot reflects
its source-only change above.

## Measurements

Release measurements used the WSL2 Linux 6.6.87.2 environment, Intel Core
Ultra 9 185H, Ubuntu clang 18.1.3, logical CPU 0 pinned, O1, core runtime,
`/home/ben/linuxbench/bench.lock`, 8,000,000 KiB virtual-memory limit and an
8,192 KiB native stack limit. Each benchmark used five runs. Times are
min/median/max in seconds; RSS is min/median/max in KiB from `/usr/bin/time`.
Wall time was captured around each direct command; no phase was computed by
subtracting another phase.

### Scalar regression

The generated E1 corpus has 10,000 functions and 500,042 source bytes. The
table compares this E2c run with E2b's five-sample S2-baseline run on the same
machine and conditions.

| Phase | E2b baseline seconds | E2c seconds | E2c peak RSS KiB |
| --- | ---: | ---: | ---: |
| Self-host compile to IR | 1.340 / 1.370 / 1.390 | 1.329 / 1.341 / 1.357 | 176,352 / 176,352 / 176,352 |
| Rust compile to IR | 0.210 / 0.210 / 0.220 | 0.234 / 0.256 / 0.272 | 82,548 / 82,728 / 82,748 |
| Whole self-host build | 6.600 / 6.750 / 6.790 | 6.731 / 6.766 / 6.975 | 245,524 / 245,524 / 245,528 |
| `link-ir` | 5.640 / 5.710 / 5.830 | 5.500 / 5.581 / 5.587 | 245,520 / 245,524 / 245,700 |
| Rust whole build | 6.020 / 6.350 / 6.460 | 6.091 / 6.249 / 6.405 | 186,136 / 186,140 / 186,144 |

The self-hosted IR grew from E2b's 6,413,374 bytes to 6,439,115 bytes
(+25,741 bytes, 0.40%). Rust IR stayed at 6,564,786 bytes. The current IR
ratios are 12.877 bytes/source byte for self-host and 13.128 for Rust. The
scalar phase medians remain close to the S2 baseline.

### Aggregate compile and runtime

`scripts/gen-e2c-bench.py` generates 128 uniquely named Result-taking functions
over `E2cBenchShape` and `E2cBenchCell`. The runtime path constructs and matches
single/pair shapes and propagates through `?` in a three-billion-iteration
long loop. It is within the input policy. Both binaries print only the
checksum, redirected to an output file: `12000000000`.

| Phase | Elapsed seconds (min / median / max) | Peak RSS KiB (min / median / max) |
| --- | ---: | ---: |
| Whole self-host build | 0.541 / 0.562 / 0.578 | 153,472 / 153,472 / 153,472 |
| Self-host compile to IR alone | 0.118 / 0.121 / 0.123 | 153,472 / 153,472 / 153,472 |
| `link-ir` alone | 0.456 / 0.501 / 0.544 | 92,584 / 92,588 / 92,652 |
| Rust whole build | 1.045 / 1.069 / 1.088 | 105,240 / 105,240 / 105,244 |

| Benchmark | Source bytes | Self-host IR bytes (bytes/source byte) | Rust IR bytes (bytes/source byte) |
| --- | ---: | ---: | ---: |
| E1 scalar | 500,042 | 6,439,115 (12.877) | 6,564,786 (13.128) |
| E2c aggregate | 50,430 | 1,132,723 (22.461) | 762,503 (15.120) |

| Direct runtime | Elapsed seconds (min / median / max) | Peak RSS KiB (min / median / max) |
| --- | ---: | ---: |
| Self-host aggregate | 1.198 / 1.219 / 1.237 | 176 / 176 / 176 |
| Rust aggregate | 21.059 / 21.231 / 21.720 | 1,584 / 1,584 / 1,584 |
| Self-host empty program | 0.00353 / 0.00377 / 0.00453 | 176 / 176 / 176 |
| Rust empty program | 0.00437 / 0.00449 / 0.00601 | 1,584 / 1,584 / 1,584 |

The first self-host runtime iteration count (1.5 billion) completed in about
0.59 seconds and did not meet the one-second requirement. The generator was
updated to three billion long iterations, the package was rebuilt by both
compilers, and all five recorded runs now exceed one second. The self-hosted
run is faster for this workload; runtime speed was reported, not used as a
gate.

The helper IR-bound comparison measured 329,851 bytes at depth 20 and 369,635
bytes at depth 40, a 39,784-byte increase. Its linear-growth check passed in
both default and long comparison modes.

### Compiler stack and native frames

`nlc inspect stacks selfhost` reports a data-stack worst case of
**6,859,732,537 bytes**, reservation **6,859,735,040 bytes**, and native-stack
worst case **8,054,624 bytes**. Against E1's 3,478,494,879-byte data bound and
3,478,495,232-byte reservation, E2c is +3,381,237,658 and +3,381,239,808
bytes. These totals are unchanged from E2b: E2c's type instances and helper
branches fit the existing compiler-table bounds.

The native-path fixture measurements below are the E2a measurements retained
for the unchanged fixtures and frame-budget path. E2c did not change slot
accounting or the frame walk. The conservative slot count, optimized function
frames, inspect-stack native path and process RSS are separate quantities.

| Fixture | Computed aggregate slots | Class | O1/O3 `-fstack-size-section` frames and native path | Observed peak RSS |
| --- | ---: | --- | --- | --- |
| `frame_budget_exact` | 1,048,576 (256 × 4,096) | build | user main 24 B; process main 40 B at O1/O3; path 65,688 B | self-host O1/O3 352/352/352 KiB; Rust O1 1,584/1,584/1,584 KiB; Rust O3 1,408/1,408/1,408 KiB |
| `frame_budget_over` | 1,052,672 (257 × 4,096) | unsupported | Rust user main 24 B; process main 40 B at O1/O3; path 65,688 B | Rust O1 1,584/1,584/1,584 KiB; Rust O3 1,408/1,408/1,408 KiB |
| `frame_budget_chain` | 1,720,320 (420 × 4,096) | unsupported | each of 8 user functions 24 B; process main 40 B at O1/O3; path 66,752 B | Rust O1 1,408/1,408/1,408 KiB; Rust O3 1,584/1,584/1,584 KiB |
| `test_frame_budget` | 12 bytes across the test and `shared` | build | test path below 1 MiB | E2a did not retain a separate RSS sample for this test-only row |

The recorded limitation remains: scalar frames, spills, LLVM inlining that
duplicates callee slots, and fixed core frames are not included in the 1 MiB
aggregate-slot budget. They share the remaining 7 MiB of the default native
stack; the follow-up is a computed native-stack bound from frame-section data.

## Reference audit and deviations

The prep brief's Stage 0 references were checked in the frozen `compiler/`
tree. The function names `option_type`, `check_builtin_constructor`,
`check_method_call`, `require_handled_result`, `emit_try`,
`emit_try_from_storage`, `emit_try_to`, `emit_print_value`,
`emit_print_value_storage` and `emit_equal_storage` exist at the cited
locations. A few line references or labels in the brief were stale:

- Option/Result method dispatch is in `check_method_call` (starting at
  `checker.rs:6533`), with the Option/Result arms around `checker.rs:8410`;
  the brief's `checker.rs:10047–10576` range is not the method implementation.
- The unwrap failure enum values are `UnwrapNone = 14` and `UnwrapErr = 15`
  around `emit.rs:22691–22692`, not at `emit.rs:22601`.
- The coalesce lowering functions are `emit_coalesce` and
  `emit_coalesce_to` at `emit.rs:18941` and `emit.rs:18976`. The cited
  `emit.rs:1681`, `4504` and `7452` occurrences are analysis traversals.
- The E2i shared exit implementation is named `lower_scope_exit` at
  `selfhost/compiler.nl:5753`; the prep's `emit_exit()` label is not the
  current interface name. E2c calls `lower_scope_exit` for propagated exits.

The references to `option_type` (`checker.rs:6309`),
`check_builtin_constructor` (`checker.rs:6438`),
`require_handled_result` (`checker.rs:3872`), the typed Try node
(`checker.rs:11221`), the Try emitter family (`emit.rs:18713–18838`),
printing (`emit.rs:17257`, `17363`) and equality (`emit.rs:19456`) were
confirmed before relying on them. Existing printing and expectation hooks were
sufficient, so no hook contract fixture was needed.

No Stage 0 reference fix was needed. Result-returning `main` remains
unsupported in E2c as required by the binding spec. `tests/run/result_coalesce`
continues to be a Stage 0 rejection with real error text; compare acceptance
uses `same_rejection` and does not pin the first error or wording.

## Acceptance and E3 merge notes

- `NLC_FRONTEND=rust cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline`: passed.
- `NLC_FRONTEND=selfhost cargo test --offline --test selfhost_interfaces`:
  passed.
- `cargo fmt --all -- --check`: passed.
- `scripts/compare-selfhost.sh --build`: 59 build, 109 diagnose,
  381 unsupported; 8 seeded builds and 8 seeded diagnostics; zero mismatches.
- `NLC_LONG_TESTS=1 scripts/compare-selfhost.sh --build`: same counts and zero
  mismatches at both O1 and O3, including all seeded cases.
- `git diff --check`: passed.

For E3a1, preserve E2c's sum-type branches in type classification, layout,
helper registration and `?`/`??` lowering while replacing native slot
addresses with data-stack offsets through E3a1's owned addressing function.
E2c did not edit `emit_layout_address`, `StorageLocation`, the hook table,
`core_sys_*` or the frame-budget walk. E3a2 should retain Result handling in
`register_package_declarations` while merging its parameter-mode and
descriptor-ABI work; propagated exits already call E2i's cleanup interface.
Keep `core/result.nl` wrappers and the audit rule intact when merging core
syscall changes, then regenerate `selfhost/core_files.nl` after the merged core
sources settle.
