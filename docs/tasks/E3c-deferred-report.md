# E3c deferred text coverage

E3c accepts bounded `Ascii`, `Text`, and `Bytes` values, while text builders
and text-containing collections remain deferred to E3d1 and E3e. The
self-hosted compiler now identifies those cases with the existing unsupported
protocol, before lowering: status 2, empty stdout, and no LLVM IR, with the
reason `text builders` or `text in collections`.

## Eligibility checks

`selfhost/deferred_text.nl` contains the shared type-graph and operation
predicates. The collection walk recognizes `Ascii`, `Text`, or `Bytes` only
when reachable below an array or list. It follows array/list elements, struct
fields, enum payloads, and `Option`/`Result` payloads. A standalone text field
or payload does not count as text in a collection, and `byte` arrays stay on
the supported path. The walk has the same 256-level recursion bound as the
existing nested-collection checker.

Typed checking defers local `Ascii +=`, `try_append` on `Ascii`/`Text`/`Bytes`,
and `Bytes.push(byte)`. It validates the receiver place, parameter mode,
argument count, and argument type before reporting `text builders`. A
`write`-mode text parameter still reports the E3c write error. For
`Bytes.push`, in-range integer literals such as 0 and 255 are checked as
`byte`; out-of-range literals remain real byte-range diagnostics. `Text +=`
and `Bytes +=` remain ordinary numeric-operator errors.

Unhinted `Ascii.empty()` retains the E3c inference diagnostic. No body-wide
name scan was added to guess whether an untyped local would later be used as a
builder.

## Directed fixtures

| Package | Coverage | Result |
| --- | --- | --- |
| `e3c_deferred_enum_text` | Text, Ascii, and Bytes enum payloads beneath an array and list | Stage0 accepts; selfhost rejects as `text in collections` |
| `e3c_deferred_option_text` | `Option<Text>` beneath an array and list | Stage0 accepts; selfhost rejects as `text in collections` |
| `e3c_values_fields` | Enum and Option text values outside collections | Builds and matches |
| `t16_collections`, `t31_collection_text_lanes` | Text values reached through struct fields in collection elements | Selfhost rejects as `text in collections` |
| `s0fix5_byte_valid` | `Bytes.push(0)` and `Bytes.push(255)` | Stage0 output `0\n255\n`; selfhost defers as `text builders` |
| `s0fix5_byte_invalid`, `s0fix5_byte_negative` | `Bytes.push(300)` and `Bytes.push(-1)` | Both compilers diagnose the invalid byte value; no IR |
| `s0fix5_grow_bytes_small`, `s0fix5_grow_text_bytes` | `try_append` through grow parameters | Selfhost defers as `text builders` |
| `t14_ascii_write_append` | `+=` through a write parameter | Real write-parameter diagnostic, not deferred |
| `t15_loop_overflow`, `t18_logsum_alignment` | Local Ascii builder operations | Selfhost defers as `text builders` |
| `t15_uninferred_loop_builder` | Unhinted `Ascii.empty()` before `+=` | Helpful E3c inference diagnostic |
| `t29_dirty_inline_copy` | Text-containing collection element | Selfhost defers as `text in collections` |

The two new type-graph fixtures include exact `expected.selfhost.stderr`
files. Their diagnostics are at `main.nl:8:17` and `main.nl:1:23`, each with
the standard `text in collections` reason.

## Validation

The frozen Stage0 reference was
`/home/ben/.cache/next-lang/target/release/nlc`. The compiler owner confirmed a
fresh integrated selfhost build and a 42-package focused comparison passed.
This task also ran the following focused comparison with
`CARGO_TARGET_DIR=/home/ben/.cache/next-lang/target` and `NLC_TEST_JOBS=1`:

```sh
scripts/compare-selfhost.sh --build \
  --reference /home/ben/.cache/next-lang/target/release/nlc \
  --only tests/run/t14_ascii_write_append \
  --only tests/run/t15_loop_overflow \
  --only tests/run/t15_uninferred_loop_builder \
  --only tests/run/t16_collections \
  --only tests/run/t18_logsum_alignment \
  --only tests/test/t29_dirty_inline_copy \
  --only tests/test/t31_collection_text_lanes \
  --only tests/e3/s0fix5_byte_valid \
  --only tests/e3/s0fix5_byte_invalid \
  --only tests/e3/s0fix5_byte_negative \
  --only tests/e3/s0fix5_grow_text_bytes \
  --only tests/e3/s0fix5_grow_bytes_small \
  --only tests/e3/e3c_deferred_enum_text \
  --only tests/e3/e3c_deferred_option_text \
  --only tests/e3/e3c_values_fields
```

At O1, all 15 packages matched: one build, four real diagnostics, ten
intentional unsupported results, and zero mismatches. The comparison verified
that unsupported cases return status 2 with empty stdout and produce no IR;
the two new type-graph diagnostics also matched their exact stderr oracles.

The first focused pass exposed that the selfhosted `Bytes.push` path rejected
in-range integer literals and mislabeled out-of-range literals as a builder
argument error. The checker was corrected to type-check the argument as a
byte before deferring. The final comparison above passed both valid and
invalid byte cases.
