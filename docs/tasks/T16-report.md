# T16 report: Text, Bytes, and growing collection values

Implemented bounded `Text` and `Bytes` across parsing, type checking, typed IR, LLVM emission, and the runtime. Text lengths count Unicode code points and carry a separate byte budget; Bytes retain raw bytes. UTF-8 validation is used for checked conversions and Text file reads. Unicode `upper()` uses the full uppercase mappings available from the build host's standard library data, with a three-code-point-per-input-code-point result bound. `Ascii` passes to read `Text` parameters as a descriptor without copying its payload. `.bytes()` is a temporary view accepted by read arguments and rejected when stored, returned, or written through.

Text and Bytes support bounded concatenation, comparisons across different maxima, slicing, length queries, output, and file IO. `fs.read`, `fs.write`, `out.write`, and `out.line` accept both types alongside T20's byte-list forms. The checker preserves the independent Text code-point and byte bounds through literals, concatenations, parameters, and function results.

Collections now store bounded Ascii, Text, and Bytes fields using inline storage through 64 bytes and non-moving size-class slots for larger maxima. Updates stage and validate their values before publishing descriptors; multi-field updates publish only after every field succeeds. Same-class replacements work at full collection capacity, shrinking keeps the current slot, and removal makes slots reusable. A runtime test hook checks that changing one field never moves another field's storage and that shrinking a field does not move it. Collection reads, copies, and cleanup follow the live-elements rules from T23. Bounded nested collections remain supported; unbounded nested growing values remain refused. Live views protect their element, enclosing storage, and collection structure from replacement, removal, shifting, and indirect write calls.

## Acceptance coverage

- `tests/test/t16_text_bytes` covers code-point and byte lengths, a four-byte code point at its maximum, Unicode uppercase expansion, invalid UTF-8 and non-ASCII conversions, inline and size-class fields, same-class replacement at full capacity, slot reuse, atomic multi-field failure, zero-copy Ascii-to-Text reads, Text/Bytes file and output IO, and invalid or oversized Text reads.
- `tests/run/t16_collections` exercises the worked `render` example and bounded Ascii, Text, and Bytes values in lists, fixed arrays, queues, rings, grids, maps, sets, pools, and nested lists. It also covers sorting Ascii values, and a collection copy that remains valid after its source is cleared.
- Additional run fixtures cover mixed maxima, byte budgets, slice bounds, Text/Bytes output, `.bytes()` argument and escape rules, and live-view write/removal/shift diagnostics. `compiler/tests/text_bytes.rs` checks that an Ascii read as Text passes its descriptor without copying payload bytes.
- Parse snapshots were refreshed for the T16 fixtures. The T14 non-ASCII literal rejection fixture now explicitly types its value as Ascii because non-ASCII string literals infer Text under T16.

## Verification

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed (41 unit and integration tests; doc-tests passed).
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed.
- `nlc inspect contracts tests/run/t16_collections` — `render` reserves a 40,016-byte caller result destination and reports a 40,172-byte requirement; `main` reports 161,558 bytes. The worked fixture prints `5280`.

With `NLC_TIMING=1`, the 1,000-term / 1,000-field checker stress fixture reported:

| Generated input | Checker time |
| --- | ---: |
| 1,000-term Text concatenation | 31.0 ms |
| 1,000-term Bytes concatenation | 24.0 ms |
| Record with 1,000 Text fields | 41.0 ms |

Each case remains well below the test's two-second bound.

## Field overflow interpretation

The task asks for a field write beyond its declared maximum to return a handled `Full`. In this language, assignment is a statement with no `Result` channel, and the checker proves that a value's declared maximum fits the destination field before generating a write. A wider value is therefore rejected at build time. Runtime failures that can occur during a staged update, such as invalid UTF-8 conversion, return their checked error and leave every field unchanged. I kept the existing assignment and error model rather than adding implicit early returns or a new field-set syntax; collection capacity failures continue to use their existing `Result<_, Full>` operations.

## Fix round 1

- Added `IoError.InvalidUtf8` for invalid UTF-8 discovered while `fs.read` validates bytes for a `Text` destination. Real read-system-call failures still use `Other(int)`; malformed file contents no longer expose Linux's `EILSEQ` number. The T16 test checks the named case.
- Added `Text.empty()` and `Bytes.empty()`. Like `Ascii.empty()`, each takes its maximum from an annotation or expected destination type and reports an error when that maximum cannot be inferred. Coverage includes annotated locals and function return destinations.
- Added `scripts/gen-unicode-upper.py` and regenerated `runtime/nl_unicode_upper.h`. The full uppercase table is generated from Unicode **15.0.0** data (`unicodedata.unidata_version`); the version appears in the header comment and in the runtime-readable `nl_unicode_version` constant.
- Refreshed the T16 test parse dump with `scripts/update-parse-dumps.sh --update`.

Verification:

- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` — passed, including all run/test fixture snapshots and doc-tests.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt -- --check` — passed.
- `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update` — passed.
