# B1 prerequisite: source-used scalar constants

Status: in progress on `work/selfhost-scalar-constants`; the name-scope prerequisite passed. This is a bounded
part of E3e pulled forward by compiler-source evidence, not full const support.

## Trigger and scope

After fixing name checks and genuine source collisions, the self-build reaches
`collections.nl:7:1`, with the unsupported-constant-declarations diagnostic. The `ed7e867`
source has 207 const declarations, all long: 194 literals, nine references, four
arithmetic expressions (in limits.nl). This subset has no builder dependency.

Implement explicit scalar long constants with signed integer literals, unary
negation, references (including forward/cross-file), and checked +, -, *, /, %.
Keep Stage0 frozen. Valid unsupported forms stay gated: aggregate/string/array
constants, constant function calls, and other scalar kinds. Do not blanket-ungate
NodeKind.Const or diagnose a valid unsupported kind as malformed.

## Integration plan

- Validate/register constants before body checking, preserving package-level
  declaration uniqueness and detecting dependency cycles.
- Resolve ordinary Name expressions after visible local bindings; a local may
  share a constant name and must win bare-name lookup.
- Mark constant facts explicitly. Literal values must not be confused with
  enum-case facts or cause a non-local Name to become an invalid local load.
- Emit scalar uses as immediate values without mutable globals or storage.
- Reuse arithmetic/capacity machinery in collections.nl where appropriate,
  with declared-type validation, memoized evaluation, and real diagnostics.
  evaluate_collection_capacity returning valid:false is not a declaration error
  message. Preserve existing capacity/overflow behavior.
- Audit const_diagnostics.nl; admitting scalar values must not accidentally
  admit unsupported aggregate `.bytes()` constants.

Likely modules: selfhost/compiler.nl, collections.nl, and the const diagnostic
helper if necessary; new fixtures and a classification block. No shared-file
parallel edits and no Rust compiler implementation changes.

## Acceptance

- Literal, negative, forward/cross-file reference, arithmetic, runtime name,
  condition, and bounded annotation/capacity cases.
- Local/constant name sharing resolves correctly; package duplicates still fail.
- Wrong long initializer types, duplicates, cycles, overflow, division/remainder
  by zero receive real diagnostics and no IR. Valid unsupported forms stay gated.
- IR evidence of immediate values, without runtime globals or uninitialized loads.
- The actual compiler declarations pass the self-build probe; report the next
  gate without claiming B1 complete.
- Preserve existing tests/oracles: classify or add packages. Use Stage0 or
  reviewed expected outputs as the oracle.

Run focused comparison and relevant capacity checks during implementation,
then the required staged-tree full suite before committing. Review arithmetic,
fact discrimination, cache/cycle behavior, and lookup precedence. Land a report
and PR only when this bounded task passes, then take the next B1 prerequisite.
