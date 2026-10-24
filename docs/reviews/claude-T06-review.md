# Review of T06 (Claude)

Approved. `cargo test` passes in my WSL run: 135 run packages, 8 test packages, and an IR test.

**Probes, all correct:**
- list `push`/`insert`/`remove`/`pop` with `Full` at capacity;
- a writable loop view over an array of structs with a nested list;
- a proven-index loop filling `long[5]` with no guards;
- proven pushes (four into a fresh `list<int, 4>` in a loop; one into a fresh `list<int, 2>`) accepted with the `Result` unused;
- `pop` under a live view refused, with the fix;
- an unproven index failing at its line.

**Accepted deviation, with follow-up:** nested collections are stored as "an array of inline collection values" (each unit's inventory keeps its own item lanes), not flattened into one lane per item field across all units as DESIGN.md's Layout section and T06 described. Semantics are identical; only memory layout and loop speed over nested items differ. Scheduled as a layout task before M4's performance work (PLAN.md).
