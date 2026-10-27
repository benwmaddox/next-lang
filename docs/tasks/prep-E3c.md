# Prep brief: E3c (Ascii, Text, Bytes, UTF-8, slicing, conversions, byte)

Status: brief for the model that writes the E3c plan. It follows docs/tasks/prep-E3a2.md. The scope comes from docs/tasks/E3-selfhost-collections-text.md: the "Parts and order" row for E3c, the "`Ascii`, `Text` and `Bytes`" section, and the "Text is validated once" rules.

## Scope checklist

E3c adds these, and nothing else:

- [ ] `byte`: the one named refinement `int 0..=255` that stage 0 defines as built in (`Checker::new`). It is admitted only where stage 0 uses it: `Bytes` elements, `b[i]` results, `Bytes.push` arguments (E3d1), and stores, casts and proofs into `byte`. General refinements, `type` aliases and `fit` on refinements stay in E4.
- [ ] `Ascii max N`, `Text max N` and `Bytes max N` as stored values in locals, struct fields and payloads, with stage 0's maximum rules. A stored value holds its length, its code-point count for `Text`, and its bytes inline at full maximum (T29). Reading one gives a transient descriptor (location, length, count) that borrows the bytes.
- [ ] Stage 0's type forms: `Text max N` (bytes default to 4N), `Text max N bytes max M`, `Text bytes max M`; `Ascii.empty()`, `Text.empty()` and `Bytes.empty()` take their maximum from the destination; untyped string literals are typed `Ascii max len` when all ASCII, else `Text`; `b"..."` is typed `Bytes max len`.
- [ ] Literals and `len`, byte access `b[i]` (failure kind 16 when out of range), comparisons, `print`, `str` and the formatting functions. Fresh-result destinations.
- [ ] Slicing `a to b` with the inclusive-range fix. Stage 0's range syntax is `a to b` (inclusive); `..=` is deprecated but accepted. Slicing fixtures use `to`, and one fixture checks that `..=` still gives the same result.
- [ ] Conversions with `Utf8Error` (a struct with `valid_up_to: long`) and `TextError` (`InvalidUtf8`, `NonAscii`), as stage 0 declares them. `validate_utf8` and `Bytes`-to-`Text` conversion return these.
- [ ] `Text` is validated once, at the places where bytes become `Text`: `Bytes`-to-`Text` conversion, `validate_utf8`, a file read into `Text` (E3f1), and literals (checked at build time). Printing, comparing, copying and writing check nothing.
- [ ] Test builds (`; nlc.build test`) re-validate every `Text` a core routine or generated path constructs, and fail with kind 22, `invalid Text constructed (compiler or core library bug)` (status 70 in a test child). Program builds never run it.
- [ ] `fit<Ascii max N>()`, which the spec's E3c row lists. This is an open question (see below).
- [ ] A Text-heavy benchmark (concatenating, slicing and printing), measured against stage 0 for the report.

Not in E3c: builders, `+=`, `try_append`, `Bytes.push`, `take` (E3d1); interpolated strings (E3d3); text lanes over 64 bytes in collections (E3e); file reads and writes (E3f1).

## Stage-0 implementation reference

- Stage 0 is the Rust `nlc` in compiler/src, frozen at tag `stage0-2026-10-26`. Read its checker for `byte`, the `Ascii`, `Text` and `Bytes` method tables, `Utf8Error` and `TextError`, range and slice typing, and the literal typing rules. Stage 0 is the source of truth for expected results.
- Stage 0 keeps behaviour the spec classes as unobservable: its pointer mode, its up-front reservation, its re-validation of `Text`, its inline nested lanes, and its 256 KiB offset-mode start. Do not port those. Port only what can be seen from a program.
- Failure text is stage 0's: kind 16 for slices and byte indexes, kind 10 for casts. Capacity is a build error or a `Result`, never a failure.
- Known stage-0 defects that touch E3c, from the E3 spec's "Language friction fixes" section, are cited there as unverified against the source. Each gets its own fixture before it is called fixed: `CONST.bytes()` on a const gives a bare "unknown enum" message (item 2, in E3c); and the slicing defect (item 4, shared with E3a1).

## Selfhost plug-in points

- Parser: the `to` range form in slices, the `Ascii` and `Text` type forms with `max`, `bytes max`, and the literal tokens `b"..."`.
- Checker: the built-in `byte` refinement and its stores, casts and proofs; the `Ascii`, `Text` and `Bytes` method tables; `Utf8Error` and `TextError` as built-in structs and their cases; the rule that a literal is `Ascii max len` only when all bytes are ASCII.
- Lowering: a stored text value is its length, count and inline bytes at full maximum. Slicing and byte access emit the bounds check with kind 16. Conversions call the validator. Test builds emit the kind 22 re-validation on each constructor path.
- Core library: UTF-8 validation and code-point counting routines are the core-library `UTF-8 in the core library` work. The E3a1 context-passing hook ABI carries them. E3c does not add a new C hook.

## Test packages moving to buildable

From tests/e1/classification.tsv. Confirm the exact rows before the plan is final.

| Row family | Lines (approx.) | Expected change |
| --- | --- | --- |
| `unit` tests for `ascii`, `byte`, `bytes`, `full`, `text` | 58-81, 118-120 | `unsupported` to `buildable` where E3c covers them |
| t14_ascii_* | 383-393 | `unsupported` to `buildable` |
| t16_* | 397-409 | `unsupported` to `buildable` |
| t20_invalid_byte | 450 | `reject`, with stage 0's kind and text |
| t24_ascii and t24_text | 463-474 | `unsupported` to `buildable` |
| t31_collection_text_lanes | 512 | stays `unsupported` until E3e |

Rows that are reject fixtures must keep stage 0's text. The selfhost diagnostic must match the first error, not every error.

## Friction items for E3c

Placed in the spec's "Language friction fixes" section:

- Item 2: `CONST.bytes()` on a const gives a bare "unknown enum 'X'". Step: E3c. Fixture: a reject case with `const` of `Ascii` and `.bytes()` on it. The message must name the const and the method.
- Item 4 (partial): a large Ascii value passed through a helper, then sliced and cast, exhausted the data stack. E3c owns the slicing part. E3a1 owns the region planning. Fixture: run under `NLC_TEST_STACK_FORCE_MOVE=1` with `NLC_STACK_STATS` on, asserting no overflow and matching output.
- Item 6: per-type exact bounds. `long` is exact at 20 characters, because the minimum long is -9223372036854775808. Fixture: the printed length of each type's extreme value, and one over the bound, which must be a build error.

## PLAN oracles for E3c

The oracles that PLAN.md names for text work. Each needs a source, a licence, and a vendoring rule before the plan is final.

1. Unicode UTF-8 decoder stress tests. Source: the Unicode Consortium's conformance material (UTF-8 well-formedness: overlong forms, surrogates, code points above U+10FFFF, truncated sequences). Use it as the validator's test set. Expected: valid inputs decode, and each invalid input gives `InvalidUtf8` with the right `valid_up_to`.
2. Case-mapping data. Source: the Unicode Character Database, `UnicodeData.txt` and `SpecialCasing.txt`. Use it only if E3c or a later step needs `upper` and `lower` beyond ASCII. Note that `upper on Text` is listed as an E3e item in the spec. E3c should not vendor the data unless the plan moves it.

Vendoring instructions to write into the plan: put each file under a new `tests/data/unicode/` directory with its version and download date, in a `README` next to it. Record the licence, which is the Unicode licence (permissive, with the notice kept). Do not edit the files. Refresh them only with a new version number. Do not add these files to `compiler/tests/`; the test set reads them from `tests/data/`.

Both data sets must be checked against the Unicode version the stage-0 core library uses, so the expected results agree.

## Pitfalls from reviews

From docs/reviews/sol-E3-r1.md, the points that apply to E3c:

- Inclusive slicing in both parsers: the selfhost and stage-0 parsers must both treat `a to b` as inclusive. Test both `to` and `..=`.
- Grow width: the `string_width_fits` bug (finding 8) matters for `str` and format width. Check it against E3c's formatting fixtures, and cross-reference E3d1 if it is the same defect.
- Bytes-only reads: a `Text` file read validates in place. This is E3f1's, but E3c's `Text` validation must already be right, or E3f1 inherits the defect.
- Error order: when a literal is invalid and a slice is out of range, the first error must match stage 0.

## Ambiguities and open questions

1. `fit<Ascii max N>()` is in E3c's row, but the "not part" list in the spec names `fit` on refinements as E4. The plan must decide whether `fit` on a text type is in E3c, and state the rule against refinement `fit`.
2. The verification status of the stage-0 defects cited in the friction items is unverified. Grep found no matching source lines. The plan must reproduce each one before it is called fixed.
3. Whether E3c's literal validation runs on the build machine or the target. The spec says build time. If stage 0 validates literals at runtime, the selfhost compiler must match its text, not its timing.
4. `..=` deprecation: is there a warning fixture, or is `..=` accepted silently? Stage 0's behaviour decides.
5. The PLAN C-binding row (a small C binding as a bridge) conflicts with the no-C decision in E3g. This does not affect E3c, but the manager should settle it before the E3 plan is final.

## Next steps

1. Confirm the classification rows in tests/e1/classification.tsv.
2. Reproduce the three friction items against stage 0 and record each result.
3. Download the two Unicode data sets into `tests/data/unicode/` with a README, in a separate change, and record the version.
4. Write the E3c plan with one fixture per checklist bullet.
5. Implement in selfhost/*.nl, then compare outputs with stage 0.
6. Write docs/tasks/E3c-report.md with the report list from the spec.

Do not edit compiler/src, selfhost/, compiler/tests/ or scripts/ in the planning step.

## Manager answers (Claude, 2026-10-27)

- **`fit<Ascii max N>`:** E3c, as the step table says; the spec's "not part of E3" line about `fit` means `fit` on numeric refinements, which stays in E4.
- **Unicode oracle data** (UnicodeData.txt, SpecialCasing.txt, the UTF-8 decoder stress tests): vendor under tests/data/unicode/ with their license files, not under compiler/tests/.
- **Stage-0 defects reported by the ports** (`CONST.bytes()`, large slicing temporaries): reproduce each as a fixture first; the self-hosted compiler must get them right, stage 0 is not fixed.
- **Errors:** only rejection with real error text is required; behaviour of valid programs must match stage 0 exactly.
