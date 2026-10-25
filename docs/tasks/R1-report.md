# R1 report: runtime arenas, buffered output, and byte matches

## Implemented

- Moved the job context into a header page in the stack mapping. The context and data stack now use mappings rather than a separately allocated context object.
- Changed `nl_fs_read_string` to read into the caller's destination and validate UTF-8 there. It leaves both output counts at zero when reading, capacity validation, or UTF-8 validation fails.
- Reworked directory listing to enumerate into caller-owned list storage using a fixed-size `getdents64` buffer, then heap-sort the live entries in place. The runtime no longer allocates a temporary entry array or duplicates each name.
- Added 64 KiB stdout and stderr buffers. They flush at context destruction, on `env.exit`, before a job failure is reported, before input reads, and on each line when writing to a terminal. Switching between stdout and stderr flushes pending output when both use the same terminal. Capability `Out` writes flush synchronously so their `Result` values still report write errors.
- Allowed integer match arms on numeric refinements such as `byte`, while retaining the wildcard catch-all requirement. Removed the cast from `selfhost/lexer.nl` and added byte-match run fixtures. The selfhost comparisons remain byte-identical.
- Added a linker-wrap heap-call test for `malloc`, `calloc`, `realloc`, `strdup`, and `free`. It counts startup calls separately and asserts zero calls during the tested program/runtime operations. A PTY probe checks stdout/stderr ordering on a shared terminal.

## Verification

Ran in WSL with `CARGO_TARGET_DIR=$HOME/.cache/next-lang/r1-target` for every Cargo command:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/r1-target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/r1-target scripts/update-parse-dumps.sh --update
ulimit -v 8000000; timeout 1200s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/r1-target cargo test
ulimit -v 8000000; timeout 1200s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/r1-target cargo build
```

All commands passed. The full test run covers the byte-match fixtures, selfhost comparisons, heap-call counts, runtime file operations, and terminal output order. C syntax checks passed for both the default and `NLC_STACK_MODE_OFFSET=1` runtime builds. `git diff --check` passed.

The generated-language heap probe exercises file writes, Text and Bytes reads, listing, formatting, printing, and collection operations in pointer mode. The current compiler rejects filesystem and other runtime calls in offset mode as outside the offset stack slice; PLAN schedules I/O and foreign offset support in O5. The offset-mode test therefore directly calls the same runtime file, listing, formatting, and output APIs and verifies zero operation-time heap calls, while collection work is covered by the generated pointer-mode program.

## Timing

Ran `bench/t32_number_output` with stdout redirected to `/dev/null` using `/usr/bin/time`. The baseline was **1.39 s** elapsed and **104,384 KiB** maximum RSS. After buffering, two runs took **0.57 s** and **0.54 s**, with **105,064 KiB** maximum RSS. This is about a 61% reduction in elapsed time, with about 680 KiB more maximum RSS.

## Remaining allocation sites

- `nl_env_create` allocates the capability environment with `calloc`; `nl_env_destroy` releases it with `free`. This is startup/cleanup state outside program operations.
- `nl_register_file` grows the source-name registry with `realloc`. This registry is populated during startup for runtime diagnostics.
- In test mode, the variable-size storage test hook allocates and frees metadata snapshots to check that updates to one field do not move or modify another field's storage.
- Under `NLC_TEST_BUILD`, the optional `NLC_TEST_REPORT_STACK_RESIDENT=1` report allocates and frees a temporary page-residency array.
- Under `NLC_STACK_VERIFY`, offset-stack growth allocates bookkeeping records for poisoned old mappings; context destruction releases those records. These calls are only for verification mode.
- Under `NLC_TEST_BUILD`, environment setup duplicates the temporary test-root path with `strdup`; test cleanup uses `opendir` and short-lived child-path `malloc`/`free` calls. These are test setup and cleanup, not language program operations.

There are no heap calls in normal runtime file reads, listings, formatting, collection operations, or buffered printing covered by the heap-call test.
