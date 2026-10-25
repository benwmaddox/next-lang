# T25 report: S1 prerequisites

## Implemented

- Added byte indexing, `Bytes.count()`, bounded `Bytes.push()` and `Bytes.try_append()`, and `grow Bytes` parameters. Byte appends use the builder's reserved region, checkpoint temporary storage, and copy only live bytes. Appending an aliased slice is safe. Push proofs track direct and bounded-loop growth; a loop whose maximum growth exceeds the buffer fails checking.
- Added `Utf8Error { valid_up_to: long }`, `Bytes.validate_utf8()`, and Rust-compatible invalid offsets from `Bytes.to_text()`. The existing T16 fixture now declares the new conversion error type.
- Added rooted `Fs.list_with_extension`. It matches the final path extension byte-for-byte, including empty extensions from trailing dots, follows symlinks beneath the filesystem root for kind classification, marks dangling or escaping links as `Other`, filters extension mismatches before capacity checks, and sorts names by raw bytes. S1 can use relative package paths inside the working directory; this is stated in `docs/syntax-tree-format.md`.
- Added `nlc lex <package>` using the same source selection, byte/UTF-8 checks, lexer, token limits, and token formatter as `parse`. It skips parsing and returns no partial output on failure. `parse --tokens` retains its existing parse behavior.

## Verification

Ran in WSL:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

All commands passed. The new integration coverage checks lex output against `parse --tokens`, syntactically invalid input, later-file errors, invalid UTF-8, 256/257 source files, 10,000 ignored entries, raw invalid-UTF-8 names, extension cases, rooted symlink kinds (including dangling and escaping targets), raw-byte sorting, and capacity failure leaving an empty list. The Bytes fixture covers checked indexing, successful and failed pushes/appends, aliasing, bounded-loop proofs, grow parameters, and overlong, surrogate, above-U+10FFFF, continuation, and truncated UTF-8 sequences.

## Timing

- Generated four comment-only `.nl` files of 16 MiB each (64 MiB package total) and ran `nlc lex` with stdout redirected. `/usr/bin/time` reported **0.09 s** elapsed and **20,792 KiB** maximum RSS.
- The 256-file Bytes integration case reads and appends 256 files of 256 KiB each, filling a `Bytes max 64 MiB` exactly, then verifies a further byte returns `Full`. The targeted end-to-end test took **0.46 s**, including package compilation and native execution.

## Decisions

- `Utf8Error` is a built-in struct, which makes its offset directly available to both validation and conversion callers.
- Directory listing includes every extension match, including directories and `Other` entries. The lexer consumer filters to `File`, as S1 requires.
- `Bytes.push()` may omit handling `Full` when the checker proves capacity, including for a statically bounded loop. An unbounded or over-capacity loop must handle the result or is rejected.

## Fix round 1

- `discard` now accepts only typed built-in capacity operations whose result error is `Full`: collection push/insert, pool add, map set, set add, and Ascii, Text, or Bytes `try_append` plus `Bytes.push`. Other Results remain rejected, even when their error type happens to be `Full`.
- Added `Text.try_append` for Text builders. It accepts Text or Ascii, checks the remaining byte and code-point limits, and updates the payload and both lengths only on success. The run fixture covers both limits and a fallible producer unwrapped with `?` before append.
- Added `tests/run/t06_discard_capacity` for the accepted forms and updated the non-Full `discard` diagnostic snapshot. Refreshed the run parse dump.

Verification:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including the run fixtures and T25 prerequisites.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed.
