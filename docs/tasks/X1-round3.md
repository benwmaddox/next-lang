# X1 round 3: cache the base, then re-measure

Round 2 (docs/tasks/X1-report.md, "Round 2") made a working offset slice and found tight list loops about 2x slower than pointer mode. Its IR shows the cause: every access calls the external runtime function `nl_context_base(ctx)`, which LLVM can't see through, so it can't hoist the base or the list count out of the loop. That's an implementation gap, not the cost of offsets themselves. The approved design (DESIGN.md "The job's data stack") keeps the base in a register like the cached top.

## Do

1. **Cache the base like the top (T13's top caching):** each function holds the base in an SSA value (a hidden argument passed alongside the context and top, or loaded once at entry from the context with a plain load), and reloads it only after a call that may grow the stack (any callee or runtime call with a nonzero data-stack requirement or that may allocate), and after growth inside the function itself (region creation, appends past the current end). No call to `nl_context_base` remains in a loop that can't grow. Derive element addresses from the cached base so LLVM can hoist invariant loads (the list count) out of loops that don't grow; add `noalias`/`nonnull`/`dereferenceable` or `invariant.group`-style attributes only where they're provably right.
2. **Keep it safe:** NLC_STACK_VERIFY=1 runs of the slice fixture still pass with the poisoned old mappings (a stale cached base would fault), at O1 and O3; add a fixture where a loop calls a growing function every k iterations and reads a list in between (the base must be reloaded after the call, and only then).
3. **Re-measure** exactly round 2's table (tight-list, struct-list, calls, builder; O1 and O3; pointer, offset dynamic, offset preallocated; best of 5), and show the new inner-loop IR next to round 2's.
4. **Then, if time allows, 32-bit offsets** scaled by 8 for the tight-list and struct-list benchmarks, with descriptor sizes.

Append "Round 3" to docs/tasks/X1-report.md: the tables, the IR, and whether the remaining cost is under 10% in tight loops (the adoption gate Ben set), with the reasons for whatever cost is left.
