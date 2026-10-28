# B1 prerequisite: Bytes fields in struct collections

Status: ready as the next serial task; scalar constants passed full staged
validation in `8dbcce0`. This is the next demonstrated compiler-source gate,
ahead of the remaining builder work.

## Trigger and bounded scope

The scalar-constant compiler's direct own-source probe stops at:

```text
collections.nl:18:12: error: not supported by the self-hosted compiler yet: text in collections
```

The parameter is `files: list<SourceFile, MAX_SOURCE_FILES>`. `SourceFile.name`
is `Bytes max 4096`, the sole current compiler field carrying text inside a
collection. The list holds 256 elements. Its name lane alone reserves
1,050,624 bytes (256 slots of an eight-byte length and 4096 bytes of payload);
this is a layout calculation, not a resident-memory measurement.

Support direct bounded Bytes fields in non-nested struct collection elements,
including this exact shape. Keep direct text collection elements, Ascii/Text
fields, nested collections, and text in sum payloads gated. Do not broaden E3e
or add unrelated constant forms. E3d1 remains required after this prerequisite.

## Implementation plan

- Narrow the deferred-text gate in `deferred_text.nl` and `compiler.nl` only
  after the admitted shape has a complete representation and operation path.
- Preserve the existing field-lane layout in `collections.nl`; audit
  `collection_field_lane_offset` and `type_group_size`, including zero capacity,
  multiple fields, and element stride. Audit related deterministic layout and
  offset fixtures before pushing any contract change.
- Implement Bytes leaves in `emit_collection_store_dynamic_fields`,
  `emit_collection_gather_dynamic_fields`, and
  `emit_collection_move_dynamic_fields`, and the admitted copy/equality paths.
  Their existing scalar fallback is insufficient for an aggregate Bytes slot.
  Reuse live-length/payload helpers from `text.nl`; preserve unused-slot rules.
- Fix indexed field addressing in `compiler.nl`: aggregate text leaves need
  their per-element field-slot stride as well. `files[i].name` must select the
  right element, including nonzero indexes.
- Preserve region/base-cache/publication rules and cover forced relocation via
  the existing harness. No new storage policy is justified by the current gate.

The source pushes records in `source.nl`, reads names for diagnostics, byte
indexing, lengths and equality, and gathers whole records in `dump.nl` and
`parse_output.nl`. These are required operations, not optional follow-up work.

## Acceptance and validation

- Stage0-matching new fixtures push distinct records, including empty, short,
  and maximum-length names. Verify nonzero indexed field reads, length, bytes,
  equality, and output. Include multiple Bytes/numeric fields to expose wrong
  lane offsets.
- Whole-element gather, list/element copies, and removal/movement preserve
  independent live bytes, element counts, and active slots. Mutating a copied
  value must not change its source.
- Keep a list live across forced data-stack relocation, then read and copy
  names again. Require evidence that the directed fixture actually relocated.
- Add negative or unsupported fixtures for the deliberately deferred shapes.
  Preserve old test contents/oracles; promote classifications from results.
- Run focused comparison and relocation selectors at O1/O3, applicable layout
  checks, formatting/diff checks, and the required exact staged full suite.
- Run the unmodified full compiler source probe and report its next gate. Do
  not claim self-hosting or B1 until the complete stage chain and corpus pass.

Use `scripts/compare-selfhost.sh --build --reference <release-nlc> --only <glob>`
and `scripts/check-selfhost-relocation.py --reference <release-nlc> --only <glob>`
with `NLC_LONG_TESTS=1`, followed by the installed pre-commit hook. Build fresh
source-keyed compiler artifacts. Stage0 implementation remains frozen.
