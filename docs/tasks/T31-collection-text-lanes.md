# T31: pointer-free text in collections

Same rules (docs/PLAN.md). From T29's report ("Data-stack addresses remaining"): T16's collection lanes for `Ascii`, `Text` and `Bytes` fields keep `{ptr, len}` descriptors pointing at each element's inline storage or size-class slot, and updates find and reuse slots through pointer-range checks. That's an address stored inside data (against DESIGN.md "The theory being tested", compactness) and something the offset milestone would otherwise have to convert.

- **Lanes store indexes and lengths, never addresses:** a field of 64 bytes or less: its length (and code-point count for Text) in one lane and its bytes in an inline byte lane of `max` bytes per element; a larger field: `{class, slot, length}` (and code points), with the class's slot array addressed by index. Reading a field builds a transient descriptor from the collection's base, the element index and the lane (or class and slot), at the use site.
- **Slot management by index:** free lists, reuse and "fits the current slot" checks use class and slot numbers, not pointer ranges; T16's staging rules (validate in temporary storage, then publish; multi-field all or nothing; same-class replacement at capacity) are unchanged.
- **Everything else unchanged in behaviour:** copies (live parts only, T23), equality, printing, sorting, maps and sets with text keys (T14's stable key copies), pools, queues, rings, grids, nested collections, globals and constants.
- **Sizes:** report per-element lane sizes before and after (a pointer per field is gone) in `inspect memory`.
- Tests: the T16, T14 and T23 fixtures unchanged; new fixtures that copy a collection of text-bearing structs and then mutate the copy and the original independently (no shared slots), dirtied-page reuse, and a check that no emitted IR stores a pointer into a lane (an IR test).
- Timing: the bench program, the self-hosted lexer and parser (best of 5, interleaved before/after).
- Report: docs/tasks/T31-report.md, updating T29's list of remaining data-stack addresses.
