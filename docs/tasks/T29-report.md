# T29 report: inline text fields in structs and payloads

## Implementation

Stored `Ascii`, `Text`, and `Bytes` values now contain their length, Text code-point count where applicable, and bounded byte array. Struct fields use these inline layouts. Enum, `Option`, and `Result` values keep their tag and inline maximum payload bytes. Locals, call results, globals, and constants use the same pointer-free storage; reading a stored string field builds a temporary `{ptr, len}` descriptor to its bytes.

Copies recursively copy fixed metadata and only the live payload bytes. The old `emit_rebase_growing_payload` path and the special pointer-bearing `%nl.option.ascii`, `%nl.option.text`, and `%nl.option.bytes` representations are gone. The T16 collection lane and size-class implementation remains in place, with its collection-specific layout and size accounting.

The emitter now distinguishes inline storage types from transient string descriptors and collection lanes. This also fixes runtime file reads into inline strings, field reads and writes, string indexing through stored Bytes fields, and returned append builders. Ascii passed to a read Text parameter continues to borrow its bytes through a transient Text descriptor without copying.

## Acceptance coverage

- `tests/run/t29_inline_text_fields` exercises struct and nested struct fields, enum payloads, `Option` and `Result` in both variants, copies, returns, equality, printing, globals, constants, and read/write parameters.
- `tests/test/t29_dirty_inline_copy` creates and shrinks a 9 MB bounded Ascii, then returns a copy. With `NLC_TEST_REPORT_STACK_TOUCHED=1`, it reports 27,000,832 bytes reserved, 8,007,680 bytes touched, and 18,000,032 bytes peak used. The compiler test checks that the live one-byte copy does not touch the full reservation.
- `compiler/tests/inline_text.rs` checks pointer-free struct/sum declarations, the inline Text fields, and the resulting memory and call-contract sizes. `Fields` is 80 bytes; each of the three globals in the fixture occupies 88 bytes after global alignment, for a 264-byte startup claim. The read and caller-result contracts for `Fields` each report 80 bytes.
- `tests/run/t24_static_string_sum` previously required a build error for a constant `Option<Ascii>`. T29 requires static string-bearing sums, so its expected result is now `true` with exit 0. Keeping that old expectation would contradict T29's constants requirement.
- The worked reservation contract changed from 40,348 to 40,332 bytes: removing the pointer from the stored `upper` value reduces the reported requirement by 16 bytes. The 40,960-byte reservation and 80-byte loop growth remain unchanged.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all run/test fixtures, parse snapshots, and doc-tests. The selfhost integration comparison passed for both lexer and parser modes, comparing status, stdout, and stderr against Rust.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed.
- `git diff --check` — passed.

## Benchmark measurements

The benchmark corpus has 13 files, 54,145 lines, and 1,152,008 bytes. Each value below is the median of three `/usr/bin/time` runs with output redirected to `/dev/null`; RSS is the median maximum RSS in KiB. Before values were measured before T29. The after runs used the final compiler and selfhost executable.

| Command | Before elapsed / RSS | After elapsed / RSS |
| --- | ---: | ---: |
| Rust `nlc lex` | 0.17 s / 23,128 KiB | 0.17 s / 23,480 KiB |
| Selfhost `lex` | 0.13 s / 14,080 KiB | 0.15 s / 14,080 KiB |
| Rust `nlc parse --tokens --tree` | 0.54 s / 72,904 KiB | 0.55 s / 72,904 KiB |
| Selfhost `parse --tokens --tree` | 0.39 s / 58,784 KiB | 0.45 s / 58,784 KiB |

An interleaved repeat of the pre-T29 and current selfhost executables measured parser medians of 0.39 s and 0.46 s, respectively, with the same 58,784 KiB RSS. The lexer stayed within timer granularity in that repeat. Rust lexer/parser times and RSS are effectively unchanged; the selfhost parser is about 15–18% slower on this corpus, while RSS is unchanged. The requested `~/nlprobe` program was not present, so these measurements use the repository's fixed selfhost benchmark corpus instead.

## Data-stack addresses remaining for X1

T29 removes stored addresses from ordinary struct fields and enum/`Option`/`Result` string payloads. These pointer paths remain:

- T16 growing collection lanes keep `%nl.ascii`, `%nl.text`, or `%nl.bytes` descriptors pointing at each element's inline (up to 64 bytes) or size-class slot. For a local collection those pointers address its data-stack lane storage; this collection representation was kept as required by T29. Collection updates also identify and reuse those slots through pointer-range checks and free lists.
- Transient string descriptors point into stack-backed locals, fields, builders, call results, collection elements, and `.bytes()` views. They are formed for reads, comparisons, printing, and IO, then consumed during the call or expression.
- The generated calling convention still uses pointers for write/grow parameters, large by-reference arguments, hidden caller result destinations, gathered collection elements, and temporary copy-back regions.
- Generated GEPs and runtime destinations retain pointers to local regions, collection lanes, loop elements, and stack-backed IO buffers. These are live compiler/runtime references, not addresses embedded in T29 struct or sum fields.

Literal and constant string descriptors can also contain pointers, but those point to static string data rather than the job's data stack.

## Fix round 1

### Profile and cause

I built the pre-T29 selfhost from commit `568af93` using an isolated source archive in `/tmp/next-lang-pre-t29` and `CARGO_TARGET_DIR=/home/ben/.cache/next-lang/pre-t29-target`. The fixed build used `/home/ben/.cache/next-lang/target`. `/usr/bin/perf` selected a wrapper with no matching WSL kernel tool, so profiling used the installed `6.8.12` binary at `/usr/lib/linux-tools/6.8.0-147-generic/perf` with `perf record -F 997 -g --call-graph dwarf` and `perf report --stdio --no-children -n --sort=symbol`.

| Selfhost build | Samples | `nl_stack_alloc` overhead | Notable callers |
| --- | ---: | ---: | --- |
| Before T29 | 334 | 35.63% (119) | `nl_fn_37_append` 17.66%; `nl_fn_0_append` 11.08% |
| T29 before fix | 389 | 41.90% (163) | `nl_fn_37` 13.88%; `nl_fn_49` 8.48%; `nl_fn_0_append` 9.25% |
| Fixed T29 | 217 | 11.98% (26) | `dump_node_fields` is no longer a leading stack-allocation caller |

The hot function `nl_fn_49` is `dump_node_fields`. Its pre-T29 IR had no `nl_stack_alloc` calls. T29 introduced 48 such calls in that function. Each read-only string label, such as `" name="`, was copied into an inline Ascii temporary; `entry_alloca` routed those larger inline temporaries through `nl_stack_alloc`, and the call then built a descriptor to the temporary bytes. The fixed IR has zero `nl_stack_alloc` calls in `dump_node_fields`.

The fix interns function string literals into static string data and emits a transient `{ptr, len}` descriptor directly to that data. This removes the per-use runtime allocation and payload copy. Assigning a literal to a stored Ascii, Text, or Bytes value still copies only its live bytes into pointer-free inline storage.

### Interleaved timings

The same 13-file, 54,145-line, 1,152,008-byte parse corpus was measured with `/usr/bin/time`, output redirected to `/dev/null`. I warmed both executables, then ran five interleaved pairs. RSS is maximum RSS in KiB.

| Run | Before T29 elapsed / RSS | Fixed T29 elapsed / RSS |
| ---: | ---: | ---: |
| 1 | 0.41 s / 58,784 KiB | 0.25 s / 58,784 KiB |
| 2 | 0.37 s / 58,784 KiB | 0.25 s / 58,784 KiB |
| 3 | 0.37 s / 58,784 KiB | 0.32 s / 58,256 KiB |
| 4 | 0.40 s / 58,784 KiB | 0.25 s / 58,784 KiB |
| 5 | 0.41 s / 58,784 KiB | 0.25 s / 58,784 KiB |
| **Best of 5** | **0.37 s** | **0.25 s** |

Added [`scripts/bench-selfhost.sh`](../../scripts/bench-selfhost.sh), which runs five parser timings on this corpus and fails when the best exceeds a generous 2.0 s bound. Its verification run measured 0.27 s best and 58,784 KiB RSS.

### Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including the selfhost lexer/parser comparison and T29 inline-text tests.
