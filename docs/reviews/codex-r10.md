# Round 10: `docs/DESIGN.md`

Reviewed state-tree commit `d5b55d0`. Concurrent uncommitted design changes are outside this review.

## 1. State cannot start empty

**Memory / Who owns state and Collections; Development experience / Restart, not swap; Types / How they are checked; One declaration, every layer / state validation.** The restart rule says “program and shared state start empty (or from what the program saved).” That worked for standalone tables, but the new root is a struct containing values and fixed arrays. `T[N]` is “always N elements,” and the example `global app: App` contains a `Tile[64 * 64]`. The design gives no rule for constructing these values before the first job runs. A zero default cannot initialize every valid state: for example, a fixed-array element of type `Int 1..100` cannot contain zero, while the array still needs all N elements. Refinements (type restrictions such as numeric ranges) are enforced when values enter the type, and state rules are checked on writes, so startup must enforce those rules too.

Specify that program and shared roots are initialized from declared valid defaults or an explicit startup initializer before jobs are scheduled; restored values receive the same checks. Lists and pools initially have zero elements unless initialized otherwise. If a field or fixed-array element has no valid default, require an initializer or report a build error. Add a Step 1 case with a fixed array of `Int 1..100`: a valid initializer starts successfully, an omitted invalid default is rejected before jobs run, and unpopulated list/pool counts begin at zero.

## Later

- **Memory / Layout and Bounds:** Count root fields once and multiply enclosing capacities to get each nested field's number of storage slots; add a nested `Text` byte-bound case.
- **Memory / Views and No overlapping arguments:** State how a view owner propagates through enclosing structs and collections, so a live view into `unit.inventory` also prevents deleting/replacing that unit or shifting an ancestor list; apply the same overlap rule to future map rehashes and ring overwrites.
- **Memory / Pools and their ids; First steps / Later:** Defer pools inside every repeated element type (including lists and pools), reject unsupported forms, and preserve generations (slot reuse counters) across any supported reset or assignment of a containing struct.
- **Frozen pools and Parallel loops:** Define builder handoff as an exception to captured read-only inputs and ordinary state ownership; Step 6 cases should check batch lifetime and one pin keeping the whole batch alive during reading.

## Questions

None.
