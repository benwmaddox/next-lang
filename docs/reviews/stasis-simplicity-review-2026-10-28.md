# Simplicity review against StasisLang

Status: review findings and proposals, not adopted language changes.
Ben requested straightforward code and a defense for Rust-derived approaches.
Recursion implementation is deferred; its unmerged prototype was removed.
Luna/max performed independent language and source reviews; Sol coordinated and
reviewed the findings. This began as a read-only review; the memory note below
records the user's current design direction. No language implementation changes
were made or tested.

## Assessment

The design carries more rules than the straightforward Stasis model. Some are
explicitly Rust-like; others, especially automatic append execution, are its own
complexity. Renaming `fn`, `Option`, or `Result` would not address the main issue.
Prioritize visible data flow, ordinary functions, explicit destinations, and
ordinary control flow over additional inference and special cases.

The comparison uses the local StasisLang `docs/spec.md` sections 7.5 and 7.8 and
`docs/knowledge/language-quick-reference.md`: caller-backed views, explicit
destinations for named aggregates, bounded storage, and optional effect checks.

## Memory baseline clarification (2026-10-28)

The current direction is two storage lifetimes: optional fixed-layout state
persisting across runs of a reusable job instance, and a moving/growing bump
arena for each run, reset at scope marks and bulk cleanup. Persistent state
cannot retain arena references, and there is no per-object heap, ownership
header, reference count, or general allocator by default. Main coordinates
startup within the CPU/core/RAM grant the host gives it; the host may grant a
subset of its resources. Main defines jobs and their counts/triggers and sets
up HTTP/mailboxes. Further per-job resource subdivision or CPU affinity is
optional policy, not a required baseline.

Only one run of a reusable job instance executes at once; parallelism comes
from additional instances. A full bounded-mailbox send returns a full status
for the caller to handle; it does not wait, drop, or retry implicitly.

The linked [Memory model, revision 1](../design/memory-revision-1.md) is a
discussion draft, not adopted syntax or compiler behavior. Job-state binding
syntax, rollback after a failed run, and arena-exhaustion behavior remain open.
The older scheduler descriptions that make `main` a worker job remain
provisional pending reconciliation.
The current runtime still runs one job per process and does not implement the
host resource grant. Snapshot versions and reference counts, frozen pools,
text-lane size classes, and zero-copy move/append paths are optional extensions;
each needs a concrete workload and a safety or measured-performance defense.

## Language findings

1. **General interfaces and owner parameters need a demonstrated use.**
   [DESIGN's interfaces](../DESIGN.md#types-and-refinement-types) specify explicit
   `impl`s, coherence, and effect contracts (lines 654-669). Pool examples also
   expose per-instance owner parameters such as `Id<P>` (lines 246-265).
   Concrete helper/comparator functions and simple named ID types would make a
   smaller initial language. Defer the general machinery until actual programs
   need it. Defense required to retain it: useful generic reuse that a simpler
   API cannot supply. Wrong-pool IDs still need protection; simplifying the
   syntax must not silently remove that guarantee.

2. **Views acquire extensive ownership rules without lifetime syntax.**
   DESIGN lines 320-333 and 450-455 combine owner/path overlap checks, mutation
   invalidation, suspension rules, and read/write/grow modes. Keep caller-backed
   parameters and short-lived loop views simple; consider deferring general
   views and finer field-disjointness proofs. Defense: prevent dangling views,
   races, and invalid LLVM alias promises. Those guarantees are real, but do not
   by themselves require a general ownership system exposed to programmers.

3. **Aggregate returns and moves obscure storage.**
   DESIGN lines 324-331 and 447-459 combine copying, `take`, implicit result
   destinations, and context-selected append execution with rollback.
   Stasis's explicit destination parameters offer one predictable alternative.
   Keep scalar returns ordinary; evaluate aggregate output parameters before
   requiring move and placement rules. Automatic append mode is not a Rust
   feature. Its defense must be measured benefit over explicit output code,
   with capacity and failure behavior preserved.

4. **Error handling has too many control-flow forms.**
   DESIGN lines 617-620 add `?`, flattening `?.`, and `??` whose alternative may
   be a value, `return`, `break`, or `continue`. `Option` and structured error
   values are useful when absence or recovery matters. Prefer ordinary branches
   and early returns initially; justify each extra operator independently.
   Likewise, collection capacity handling at line 231 adds a built-in-only
   `discard` exception. Consider a consistent checked-operation API instead of
   more origin-sensitive rules. Do not lose error information where callers
   actually need to recover.

5. **Return style should be consistent.**
   DESIGN line 996 allows explicit returns and final expressions while leaving
   their grammar to be specified. Stasis's explicit `return` is an available simple
   default. This is a clarity choice rather than a memory-safety requirement.

## Local code simplifications

These can be evaluated separately from language redesign:

- `selfhost/main.nl:124` and `selfhost/compiler.nl:720`: centralize repeated
  diagnostic writes and their identical exit-on-write-error branches.
- `core/context.nl:159` and `core/output.nl:44`: replace check-then-unwrap with
  one branch that binds the successful value where that makes cleanup clearer.
- `selfhost/compiler.nl:156` and `selfhost/params.nl:28`: give storage-anchor
  numeric tags meaningful names; the location descriptor itself is necessary.
- `selfhost/compiler.nl:11451`: centralize destination-state save/set/restore
  rather than repeating three mutable fields around expression emission.
- `selfhost/regions.nl:236`: compute a node's owning block once instead of
  repeatedly scanning blocks while planning temporary regions.

These are review candidates, not benchmark claims or completed fixes. Fixed
capacities, caller-owned workspace, and explicit worklists already fit Stasis's
style and the bounded-memory goal; they are not evidence of Rust drift.

Before adding a complex rule, require a short ordinary program showing the need,
the simplest explicit alternative, its safety trade-off, and measurements if the
reason is performance. No language redesign was implemented in this review.
