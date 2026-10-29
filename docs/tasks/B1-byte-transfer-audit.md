# B1 byte-transfer audit

Status, 2026-10-29: the four `selfhost/text.nl` transfer helpers and three
IR-writer helpers below were implemented in source commit `4744334` (PR #15).
The Stage3 corpus and targeted writer/relocation checks passed. The warm matrix
was recorded under the historical 3x criterion; its aggregate timings do not
show what these individual copies contributed. All three cases exceed the
current 1.1x speed goal.
This remains a structural inventory, not an exhaustive proof from grep. Core
I/O replacement remains deferred. `selfhost/text.nl` line references below are
pre-change audit locations; function names identify the reviewed helpers.

## Selfhost compiler paths

| Priority | Location | Original cost and outcome |
|---|---|---|
| High | `selfhost/text.nl:317-370`, `emit_text_bytes_view` | The original generated code copied each byte into a Bytes temporary. It now calls `memmove` and keeps the length store, matching Stage0's `compiler/src/emit.rs:13355-13367` strategy. |
| High | `selfhost/text.nl:375-455`, `emit_text_literal_value` | The original non-core generated code copied static literal bytes with a runtime loop. It now moves `literal.count()` bytes from the literal global and retains the length and Text point-count fields without copying the terminator. |
| High | `selfhost/text.nl:694-810`, `emit_text_slice` | The codepoint scan that computes byte offsets remains. The payload loop now uses `memmove`, matching Stage0's `emit_string_slice_to` at `compiler/src/emit.rs:13443`; result length and point-count stores remain. |
| Medium | `selfhost/text.nl:1659-1709`, `emit_text_copy_range`; called by `emit_text_concat` at `:1753-1755` | The original per-byte operand copies now use overlap-safe `memmove` per span. Existing lengths and Text point counts remain. No matching Rust `TextConcat` node was found. |
| Medium | `selfhost/compiler.nl:8577-8589`, `ir_write_ascii` / `ir_write_bytes` / `ir_write_number` (audited pre-change form) | The old ASCII/number fallback loops indexed `value.bytes()[index]` (`ir_write_number` formatted via `str`); the Bytes fallback indexed `value[index]`. The new normal path uses bulk append; `Full` retains the byte fallback and accepted-prefix behavior, and number output delegates to ASCII. The 15-case writer probe matched old/new results at O1/O3. Stage0 also materializes `.bytes()` but uses `memmove`; the pointer/offset difference means aggregate timing is not a per-helper comparison. |

The four text-helper changes and three writer-helper changes are implemented and
validated in `4744334`. The writer probe checks 15 byte/overflow goldens at O1
and O3; the full Stage3 corpus covers 792 registered plus 256 seeded cases at
both levels with zero mismatches. See
[`B1-byte-output-checkpoint.md`](B1-byte-output-checkpoint.md) for the complete
validation and timing limits.

## Other reviewed paths

| Location | Classification |
|---|---|
| `core/output.nl:130,157-170`, `nl_core_output_write` | Copies each buffered chunk byte by byte; a bulk move can replace the transfer. Keep the newline scan. This is the separate core-mode path; the selfhost C-runtime output path already uses `memchr` and `memcpy` in `runtime/nl_runtime.c:1787-1793`. |
| `core/memory.nl:24-29`, `copy_backward` | Large overlapping moves use a byte loop. Consider descending `sys.copy_16` blocks plus a bounded tail, preserving overlap order. Forward copy already uses bulk and 16-byte operations. |
| `core/text_format.nl:44-60,65-82` | Zero padding, space padding, and payload copy use loops. Existing `memset`/`memmove` helpers are suitable; C-runtime equivalents use them in `runtime/nl_runtime.c:1109-1123,1196-1210`. |
| `selfhost/parse_output.nl:7-17,259-267,957-959,1001-1003` | Diagnostic source spans, small dump fields, file names, and binary-tree source serialization append raw bytes through per-byte pushes. Chunked bulk append is a debug/error-path opportunity; binary-tree mode may serialize up to the package source cap. |

The selfhost source read path is already bulk: `selfhost/source.nl:263` reads
Bytes through `nl_fs_read_string` in chunks, and `:290` uses `source.try_append`.
The C output path batches writes and copies with `memcpy`. C-runtime loops for
`list<byte>` validate and convert its 32-bit lanes; they are representation
conversions, not raw-span transfers.

## Keep bytewise logic where it inspects or transforms data

Lexer/parser token inspection, UTF-8 validation and boundary finding, JSON
escaping, hashing, substring search, newline detection, and numeric digit
construction perform per-byte decisions or transformations. Preserve those
semantics when optimizing adjacent payload copies. Path and diagnostic name
conversion from `list<byte>` to Bytes is also a representation conversion.

## Current disposition and follow-up

The seven transfer changes are complete. The remaining core-output,
backward-copy, formatting, and diagnostic-serialization loops above are
lower-priority candidates, not evidence that every byte loop is wrong. Preserve
loops that inspect or transform individual bytes. Core I/O replacement remains
deferred. The separate direct scalar field-projection opportunity is documented
in [`B1-stage1-stage2-comparison.md`](B1-stage1-stage2-comparison.md). Treat
selfhost as a stress workload and assess general indexed-field lowering such as
`rows[i].field` across varied inputs; do not special-case selfhost or add a
language rule. Compare correct arena strategies against the current checkpoint's
1.1x goal.
