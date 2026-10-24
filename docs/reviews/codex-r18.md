# Round 18 review

## 1. Contradictions and exact fixes

- **Indirect calls lack a complete contract (`Types`, “Functions as values, no closures”).** An indirect call invokes a function through a value. Its type lists effects and a stack window, but not parameter modes, per-stack/native byte bounds, result bounds, fresh-result/append support, or whether it may suspend. Include these in its contract and indirect edges in stack and recursion-cycle analysis. A stack contract specifies scratch space and input/result placement. For saves/replays, replace process addresses with symbolic function IDs checked against the build, or forbid persisted function values.

- **Block context needs rules (`The language in one page`, lines 66, 85–87, 106–108; `Parallel loops`, line 420).** A closure bundles a function with captured locals. `post(room_key)` looks like partial application: supplying only some arguments. Define it as a declarative action binding (function ID plus bounded argument copy); dispatch supplies remaining arguments/capabilities. Specify database/transaction blocks, routes and parallel bodies as scoped syntax compiled into top-level helpers with explicit context; replace “captured caller values” accordingly. Extend the existing query-expression exception.

- **`?.`/`??` mix `Option` and `Result` (`The language in one page`, lines 61–62, 87).** Define `?.` to evaluate its receiver once, skip the call on `none`, and return `Option<U>`. Limit `??` to an Option default or early return, evaluated only when absent. The transaction returns `Result`, so replace its `?? return err(PostError.Full)` with an exhaustive `match` handling the actual error variants; don't discard unrelated errors as `Full`.

- **Snapshot dependencies need consistent contracts (`Effects and capabilities`, line 586; overview, line 115).** Distinguish explicit user context from compiler-supplied snapshot context. Record snapshot access in the function contract and pass the pinned version as a hidden argument, including indirect calls; after suspension use a fresh snapshot. Describe the overview's snapshot read as a dependency, not an effect, matching line 586. Carry program/job-state access metadata too, preventing incorrect caching.

- **Worked-example wording and scratch (`How the compiler assigns stacks`, lines 351–377).** Change the introduction's two `Text` results to `Ascii`, matching the code. Its later Unicode variant is explicitly separate. Strengthen `str`'s contract: while `name` occupies stack 1, formatting appends directly to destination 0 with no growing scratch; otherwise recalculate `N = 2` and the peak.

- **32-bit arithmetic needs boundaries (`Numbers`; refinement/index rules).** A refinement is a base type plus a checkable bound. `int 0..1000` already correctly separates 16-bit storage from 32-bit arithmetic; additionally reject bounds outside `int`'s range. Use a `long` accumulator for large sums and widen operands before multiplication/addition; casting an overflowing result is too late. The worked example's 500 counts total at most 499,999,500; 10,000 can total 9,999,990,000. Define `len()`, counts, offsets and `Index(a)` as refined `long`; check capacity products in 64 bits and extend unsigned pool slots without changing their value. Give timestamps/durations distinct `long` types with declared units. Specify mixed-type arithmetic rules.

- **`fast` changes float precision (`Numbers`, “Floats”).** It says fast results are always `double nan`, although the same section supports `float nan`. Preserve operand precision: float operations yield `float nan`, double operations `double nan`; check NaN on conversion to the corresponding plain type.

- **Literals and C widths (`Numbers`, lines 500/508; `Interop`, line 712).** State that suffixes fix literal types; context selects only unsuffixed literals, otherwise defaults apply. Replace “integers as 64-bit…floats as double” with declared-width mappings to C prototypes and explicit checked conversions; packed state layout isn't automatically C layout.

- **Keep current and historical conversion rules distinct (`Numbers`; review history).** No stale `Int`/`Float`/`Bool` names remain. The old Flow-era “no implicit conversions” rule was replaced by proposed implicit lossless widening and checked narrowing; label the latter unconfirmed rather than claiming both are current. In the x86 safe-start paragraph, replace “below the minimum target” with “no higher than the selected minimum”: Android's safe-start and minimum are both v2.

## 2. Closure-free patterns

- **Sorting:** `sort_by(items, ctx, compare)`; `compare(ctx, a, b)` is named and pure, with read-only context disjoint from sorted storage.
- **Callbacks:** synchronous calls borrow explicit context. Retained callbacks need an owned bounded record or typed ID; cancel before its owner expires. C callbacks use a trampoline (a binding wrapper) that dispatches the named handler on its owner's worker.
- **Events:** queue `{handler_id, target_id, bounded_payload}`; dispatch resolves the name and supplies world/capabilities. This avoids unsaveable pointers.
- **Parallel work:** use a named body and read-only context with per-item disjoint outputs; join before caller storage or snapshot context ends.
- **Page pieces:** use top-level pieces with bounded plain arguments; `serve` supplies fresh capabilities on render/refresh. Bind `post(room_key)` declaratively as above.

## 3. Questions for Ben

1. **Conversions:** (A) implicit lossless integer widening only; (B) C#-style widening. Recommend A until mixed signed/unsigned rules are explicit; keep narrowing checked and `unchecked` cast-only.
2. **Large indexes:** (A) `long` lengths, capacities, offsets and indexes; (B) keep `int` and reject larger collections. Recommend A for 64-bit targets.
3. **Scoped server blocks:** (A) named helpers only; (B) route/transaction/action blocks lowered to named helpers plus explicit context. Recommend B for readable server code without user closures.
