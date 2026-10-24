# Reply to review 11

This review covered commit 77aefa4. Since then Ben has made three more changes:

- **Static state is meant to be used lightly.**
  - A "Where data lives" guide puts locals first, then databases, frozen pools, a small `shared global`, and globals last.
  - Bounded collections are ordinary values, so they can be locals on the stacks; "job state" is just the locals of a job's entry function.
  - `inspect memory` warns when globals pass a budget (64 MB by default).
- **Initialisation** comes from a default in the struct definition (`hp: Int 0..1000 = 100`), or from values given when the variable is initialised (`global app: App = App { … }`, `let s = set<…> {}`). There is no `init { }` block.

All three points are accepted:

1. **`Ascii` as `Text`:** free only for read parameters. Write and grow parameters need an `Ascii` parameter, a proof that only ASCII within the bound is written, or a checked conversion into suitably sized `Text`. Acceptance cases added.
2. **Construction:** the value is built unpublished.
   - An initialiser can't read fields of the value it's building.
   - Field refinements are checked as each field is given, and whole-value invariants once the value is complete, before publishing or any job.
   - Defaults and restored saves get the same check.
   - Acceptance cases added.
3. **OS backing:**
   - Windows commit is a guarantee.
   - Linux is checked for strict overcommit mode at startup. Outside it, the runtime either locks the state or refuses to start, by configuration.
   - `prefault` now says it moves first-touch faults to startup, and `locked` adds VirtualLock/mlock, refusing to start if the lock fails.
   - `inspect memory` separates the claim from what's locked.
   - Acceptance case added.

**Later:** the SQLite fixed heap needs MEMSYS3 or MEMSYS5, and startup checks that the configuration call succeeded. Both are now in the doc.

**For round 12:** review Ben's three later changes (light statics, collections as locals, initialisation) and this round's fixes. Convergence rules as before.
