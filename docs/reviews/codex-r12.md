# Round 12: `docs/DESIGN.md`

Reviewed `f7a3fe4`, including Ben's changes in `cf2662f` and `4ed5ed6`.

## 1. Local collections have conflicting storage and accounting rules

**Memory / State; Collections; Who owns state; Static allocation.** State is described as sized and reserved once at startup, and the “Not on the data stacks” rule says state memory has its own reservation. But locals are included in the state tree and called “job state,” while Collections says a local collection over 4 KB lives on the fixed-scratch stack. For example, `let xs = list<Int, 1000> {}` in a job is both state with a separate reservation and a stack local. This leaves step 1's placement, peak stack memory and admission accounting (deciding whether another job fits the memory budget) unclear.

Limit the state-reservation and “Not on the data stacks” rules to globals and shared globals. Say that local bounded collections, including those over 4 KB, count toward the job's stack reservation and admission, and report them in `inspect stacks`. **Acceptance:** step 1 builds a >4 KB local list and a nested local list; returning or copying a local list keeps its contents valid after the source scope ends, and a loop iteration frees its scratch without freeing the outer list.

## 2. Local initialization timing is underspecified

**Static allocation / Initialised before any job runs; Correctness tools / Invariants.** The rule lists globals and locals alike, then says the completed value is checked before any job runs; it also says that after startup, the every-write invariant rule applies. A local struct can be constructed inside a running job, so the construction exception needs to depend on that value's completion, rather than program startup. For `let s = Span { start: 10, end: 20 }`, validate its invariant (a rule relating fields, such as `start <= end`) when this local is complete, not while only `start` has been assigned.

Separate the timings: validate each global root before scheduling jobs; construct each local privately at its declaration, check field refinements (per-field restrictions) as fields are supplied, then check whole-value invariants before making that value usable. Apply ordinary write checks after each value is published. **Acceptance:** a job constructs and uses a valid `Span`; an invalid completed `Span` fails that job without exposing a partial value.

## 3. Strict overcommit mode does not establish the backing promise in cgroups

**Static allocation / Linux.** Strict overcommit mode limits system-wide memory promises; it does not certify backing within a cgroup (an OS resource group, commonly used for containers). The kernel documents `memory.max` as a separate hard group limit that can trigger process termination when memory cannot be reclaimed ([Linux cgroup v2 memory controller](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory)). Thus a successful address-space mapping, even in strict mode, does not guarantee that the group can pay for pages when first used. This is an inference from the separate system-wide and group limits.

Keep the no-growth global allocation rule, but for supported, stable deployment limits, account for the effective cgroup memory and swap limits plus required job headroom, and charge state at startup before scheduling jobs; refuse startup if the configured backing guarantee cannot be met. Checking limits alone does not reserve them. Describe the guarantee as conditional on supported OS limits remaining unchanged, with OS termination outside the contract. **Acceptance:** in a tight cgroup, a successful mapping whose state exceeds the effective limit does not proceed to job scheduling.

## Shared immutable data across threads

Yes. Frozen pools store nodes in arrays and text in payload blocks; typed ids link nodes. Workers build separate partitions, then freeze them without copying. Readers share views, with one pin (a promise to keep the batch alive) per read phase and no per-node counting. Blocks are freed in bulk after the creating scope ends and the last reader releases its pin. Mutable locals remain job-private. A global interner (a store that keeps one copy of each distinct value) still needs one writer or per-thread construction and a merge. Builder handoff and lifetime cases remain for step 6; these changes add no step 1–2 blocker.

## Later

- Specify identity and generation behavior for copying, returning or resetting local pools before those operations are supported; a returned pool may acquire the caller's owner name.
- Distinguish bounded `list<Text max N, C>` from growing `List<Text>` in database and rendering examples.
- State the backing policy for macOS and Android.

## Questions

None.
