# T32 report: faster operator matching and number output

Replaced the self-hosted lexer's operator matcher chain with a first-byte `match` and short checks for the following bytes. The operator spellings, token positions, and errors still match the Rust reference.

Added a decimal formatter that determines the digit count, then writes two digits at a time from a 200-byte pair table. The general radix formatter remains in use for bases 2, 8, and 16. Integer `print`, raw numeric printing, and `Out` integer writes now use the fast formatter.

Decimal values streamed into Ascii, Text, and Bytes builders are capacity-checked and written directly into the builder's free space. The Bytes form is `str(n).bytes()`, because `Bytes.try_append` takes a Bytes view; the emitter recognizes that view around a decimal format. Other append forms keep their existing paths.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed under an 8,000,000 KiB virtual-memory limit and a 180-second timeout.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed under the same memory limit and a 900-second timeout, including the self-host comparison and all language fixtures.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` and `git diff --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed; snapshots were added for both T32 language fixtures.
- `scripts/compare-selfhost.sh --tokens ...` — passed for 374 packages, 42 directed and limit cases, 300 byte mutations, and the 54,145-line benchmark.
- `scripts/compare-selfhost.sh --parse ...` — passed for 374 packages, 103 directed and limit cases, 300 byte mutations, 300 parser tree mutations, and the same benchmark. Status, stdout, and stderr matched the Rust reference.
- The formatter runtime test compared every decimal digit boundary from 10 through 10^18, signed int and long extrema, and three million deterministic random values against the general routine. All comparisons passed. It also confirms the base-2, base-8, and base-16 paths still match the general routine.
- The builder emission test confirms Ascii, Text, and Bytes decimal appends call the size helper and formatter directly, with no `memmove` staging copy. Language tests cover exact output and `Full` leaving each builder unchanged. The print fixture covers zero, negative values, and int/long extrema.

## Running

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` runs the compiler, language, and self-host comparison tests.
- `nlc test tests/test/t32_number_format` runs the boundary and builder tests; `nlc run tests/run/t32_decimal_print` prints the integer extrema fixture.
- `nlc build bench/t32_number_output -o /tmp/t32-number-output && /tmp/t32-number-output >/dev/null` runs the ten-million-number timing workload.
- For the self-host corpus, run `scripts/gen-bench-corpus.sh .t32-benchmark --parse`, then build `selfhost` and run its `lex .t32-benchmark` or `parse .t32-benchmark --tokens --tree` command.

## Measurements

The self-host lexer and parser benchmarks used the 13-file, 54,145-line corpus from `scripts/gen-bench-corpus.sh`. Before and after binaries were run in alternating order for five runs each. The before binaries came from clean HEAD `cae5a1f3f08a368d1fffcb114a6a87b6e0a2abe9`; the after binaries included T32. The number-output workload is [main.nl](../../bench/t32_number_output/main.nl), compiled at both revisions and run with stdout redirected to `/dev/null`.

| Workload | Before runs (s) | After runs (s) | Best before | Best after | Peak RSS before → after |
| --- | --- | --- | ---: | ---: | ---: |
| Self-host `lex` | 0.10, 0.11, 0.14, 0.10, 0.10 | 0.08, 0.08, 0.08, 0.08, 0.08 | 0.10 s | 0.08 s | 13,904–14,080 → 13,904–14,080 KiB |
| Self-host `parse --tokens --tree` | 0.29, 0.28, 0.29, 0.28, 0.28 | 0.25, 0.24, 0.25, 0.24, 0.26 | 0.28 s | 0.24 s | 58,784 → 58,784 KiB |
| Print 10 million longs | 1.20, 1.19, 1.17, 1.15, 1.16 | 0.90, 0.91, 0.90, 0.90, 0.90 | 1.15 s | 0.90 s | 1,584 → 1,408 KiB |

Profiles were collected with `/usr/lib/linux-tools/6.8.0-147-generic/perf` and `perf report --stdio --no-children -n --sort=symbol`. Repeating the lex workload ten times produced 468 samples with no lost samples. The largest self costs were `output_token_dump` 30.98%, `memmove` 16.67%, `nl_stack_alloc` 11.54%, `nl_ascii_format_i64_decimal` 10.68%, `lex_file` 8.97%, and `emit_token` 6.20%. `matches_ascii` no longer appears. Repeating parse five times produced 1,006 samples: `nl_stack_alloc` 8.85%, `nl_context_set_top` 8.05%, `output_token_dump` 7.06%, `memmove` 6.66%, and `nl_ascii_format_i64_decimal` 5.77%. The print workload produced 442 samples: `write` 64.03%, decimal formatting 18.55%, `nl_print_bytes` 13.12%, and `nl_print_long` 3.39%.

## Remaining work and choices

The lexer casts the byte to `int` for the dispatch match because current `match` typing does not accept `byte`; the value remains in 0–255. Inline stack allocation is still scheduled for O1. No external crates were added.
