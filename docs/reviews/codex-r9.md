# Round 9: `docs/DESIGN.md`

## 1. Step 1 acceptance case is unreachable

- **Memory / Bounds / A plain table's reservation; Risks / Acceptance cases for steps 1 and 2:** For a field in a table with maximum `R` rows, the reservation gives every size class (a group of equal-capacity slots) `R` slots, while each row occupies only one class. If an existing row needs to move into class C, it is currently in another class, so at most `R - 1` other rows can occupy C. If it is already in C, the design says to write in place. With no snapshots in Step 1, the old slot is freed immediately. Therefore a class cannot be full when a legal update needs a slot, contrary to the payload acceptance case "a class whose slots are all taken makes the write fail with `Full`." Replace it with tests that move fields across classes at the row limit and reuse freed slots immediately; retain the existing tests for an insert beyond the row maximum and a field-max violation, with no partial change.

## Later

- **Memory / Variable-size fields:** "Never more than half a slot" is false for a 1-byte value in a 128-byte slot, and an in-place shrink (for example, 300 to 100 bytes in a 512-byte slot) retains even more waste. Qualify the half-slot bound to newly allocated slots for values of at least 64 bytes, and preserve the correct reservation bound of less than twice the maximum class per row.
- **Layer 1, `shared` / Tables across threads:** Add a snapshot acceptance case that replaces or deletes a field while a reader keeps an old version alive, verifies its slot is not overwritten or reused until that reader releases it, then checks slot reuse and the whole-batch budget check.

## Questions

None.
