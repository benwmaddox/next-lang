# Reply to review 18

**Ben's decisions (2026-10-24):**
- **No implicit conversions at all,** widening included. That supersedes the proposal you reviewed, and your question 1.
- **Lengths, counts, capacities, offsets and indexes are refined `long`s** (your question 2, option A).
- **Scoped blocks are allowed** (your question 3, option B): `db.read`, `db.transaction`, `transaction`, routes, `parallel for` bodies, and a page's `for` and `if`. Each is turned into a named helper with explicit, bounded context; none can be stored, returned or called later.

**Point 1, all applied:**
- **Indirect calls:** a function type is now a full contract: parameter modes, result and append mode, effects, may-suspend, snapshot or state access, and per-stack and native byte bounds. Call-graph analyses follow indirect edges. Saves store function values as symbolic ids checked against the build.
- **Bindings:** `post(room_key)` and `signal Messages(room_key)` are declarative bindings, recorded as a function id plus bounded arguments. The server supplies the rest. A new "Bindings aren't closures" bullet covers them.
- **`?.` and `??`:** defined, and Option-only. The transaction in the example uses an exhaustive `match` on `DbError.Full`.
- **Snapshots:** a snapshot read is a dependency passed as a hidden argument and recorded in the contract, not an effect. The overview's wording is fixed.
- **Worked example:** the intro says `Ascii`. `str` writes straight onto its destination with no scratch, otherwise N and the peak would be worked out again.
- **32-bit arithmetic:**
  - refinement bounds must fit their base type;
  - large sums use `long` accumulators, with operands cast first;
  - capacity products are computed in 64 bits;
  - `Time` and `Duration` are distinct `long`-based types with units.
- **`fast` precision:** keeps the operand's type (`float nan` or `double nan`).
- **Literals:** a suffix fixes the type; an unsuffixed literal takes its type from context, or defaults to `int` (or `double` when it has a decimal point).
- **Interop:** C prototypes use the declared widths, and state's packed storage is never handed to C directly.
- **Safe start:** "no higher than the selected minimum" (on Android the two are equal).

**Point 2:** the closure-free patterns are in the doc (sorting, callbacks, events, parallel work, page pieces), with C callbacks going through a generated wrapper.

**For round 19:** a convergence check of these changes.
