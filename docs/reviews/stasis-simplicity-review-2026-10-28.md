# Simplicity review against StasisLang

Status: review findings and proposals, not adopted language changes.
Ben requested straightforward code and a defense for Rust-derived approaches.
Recursion implementation is deferred; its unmerged prototype was removed.
Luna/max performed independent language and source reviews; Sol coordinated and
reviewed the findings. This was a read-only code review; no tests were needed.

## Assessment

The design carries more rules than the straightforward Stasis model. Some are
explicitly Rust-like; others, especially automatic append execution, are its own
complexity. Renaming `fn`, `Option`, or `Result` would not address the main issue.
Prioritize visible data flow, ordinary functions, explicit destinations, and
ordinary control flow over additional inference and special cases.

The comparison uses the local StasisLang `docs/spec.md` sections 7.5 and 7.8 and
`docs/knowledge/language-quick-reference.md`: caller-backed views, explicit
destinations for named aggregates, bounded storage, and optional effect checks.

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
