# T27 report: self-hosted parser stack attribution

## Before and after

| `nlc inspect stacks selfhost` | Before | After |
| --- | ---: | ---: |
| Data stack worst case | 192,745,324,820 B | 904,669,490 B |
| Data stack reservation | 192,745,328,640 B | 904,671,232 B |

The former output did not identify a critical path. The new attribution is:

```text
main -> output_tree_dump -> dump_node_line -> dump_node_fields
     -> dump_quoted_decoded_token -> decode_string_token
     -> append_unicode_byte_value
```

| Contribution on that path | Bytes |
| --- | ---: |
| `main.nl:49 main.entries` | 67,158,024 |
| `main.nl:50 main.source` | 67,108,880 |
| `main.nl:51 main.files` | 2,095,208 |
| `main.nl:52 main.tokens` | 100,000,008 |
| `main.nl:53 main.delimiters` | 8,200 |
| `main.nl:54 main.file_data` | 16,777,232 |
| `main.nl:64 main.tables` | 616,907,937 |
| `main` call/expression scratch | 381 |
| `parse_output.nl:832 output_tree_dump.buffer` | 1,048,592 |
| `parse_output.nl:834 output_tree_dump.file` | 4,168 |
| `output_tree_dump` call/expression scratch | 4,207 |
| `dump_node_line` call/expression scratch | 834 |
| `dump_node_fields` call/expression scratch | 1,099 |
| `parse_output.nl:424 dump_quoted_decoded_token.value` | 16,777,232 |
| `parse_output.nl:364 decode_string_token.value` | 16,777,232 |
| Data-stack helper margin | 256 |
| **Attributed sum** | **904,669,490** |

The seven large `main` regions total 870,055,489 bytes. The rest of the bound is the output path's bounded buffers and scratch plus the 256-byte runtime helper margin. `inspect stacks` now checks and prints that its contribution sum exactly matches the bound.

## Cause and fixes

The 192 GB result was an analyzer overcount. For large arguments, it treated place expressions as copied staging values. In particular, `ParseTables` arguments such as `write ParseTables` were counted as temporary copies at each call, even though the emitter passes these large values by pointer. Calls through the parser helpers accumulated those fictitious copies along the call path. The analyzer now counts non-place large arguments and still counts actual structure-of-arrays element gathers at their indexing expressions. The self-host stack-contract test keeps the result below 1 GB and checks the exact `main.tables` contribution.

The analyzer also used a byte collection's declared maximum for static byte-string arguments. It now uses the literal's actual storage size. The emitter stages static byte strings at that exact size, and I/O extension arguments use the same path. A `Bytes`-returning call written into a destination now builds in that destination instead of keeping a second hidden result buffer live.

`dump_bytes` in `selfhost/parse_output.nl` only receives short fixed spellings and escape fragments, so its parameter maximum is now 64 bytes instead of 64 MiB. Number and hex spellings are pushed byte by byte. The five `buffer = Bytes.empty()` sites in `selfhost/dump.nl` no longer need copy-down regions; empty resets update the descriptor without allocating replacement payload storage. The output-token-dump contract has no copy-down sites.

While running the full suite, the T25 filesystem-listing case exposed another attribution omission: a large iteration element inside a `match` arm was absent from the function's local-region requirement. Region analysis now walks blocks nested in `if` and `match` expressions, and a regression test covers a loop in a match arm.

## Recursion and target interpretation

T19's rule still holds: no large data-stack region may remain live across a recursive call. The stack analysis counts a recursive call cycle once, independent of recursion depth. T19 checks the recursive region rule, while the native stack is controlled by the runtime recursion budget; selfhost's budget is now 7,800 KiB so that budget does not preempt the parser's own 1,000-level nesting diagnostic. Runtime recursion checks still use the available native stack limit.

The final bound is 904.7 MB (863 MiB), or 1.47 times the compiler-sized `main.tables` region. This is below 1 GB and within a small factor of the parser's declared fixed-capacity storage. It is not literally “a few hundred MB”: existing selfhost limits reserve 870.1 MB for the simultaneously live `main` regions, including the 616.9 MB parse tables, source/token storage, directory entries, and per-file buffer. I kept those input and parser limits intact; lowering the reported total further would require changing those capacities or their storage model. Every remaining contribution is a declared reserve-ahead region or bounded output-path storage.

## Measured use and verification

The one-GiB reservation probe reported:

```text
computed worst case: 1,000,000,264 B
reservation:         1,000,001,536 B
measured peak use:   1,000,000,008 B
touched pages:           8,003,584 B
```

The measured peak remains below its computed bound. The self-host lexer/parser comparison also passes on the benchmark set (13 files, 54,145 lines, 1,152,008 bytes), and its run completes under the 904,671,232-byte computed reservation.

Verification from WSL:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including self-host comparison, stack contracts and measured peak, and all T25 prerequisites.
- `NLC_TEST_REPORT_STACK_TOUCHED=1 $HOME/.cache/next-lang/target/debug/nlc test tests/test/t17_large_reservation` — passed with the measurements above.

No external crates were added.
