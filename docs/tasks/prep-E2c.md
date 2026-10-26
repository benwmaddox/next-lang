# E2c prep brief: Option/Result, `?`, `??`, and core error wrappers

## Scope checklist

- [x] Option and Result interning during type checking
- [x] Built-in constructors: `some`, `none`, `ok`, `err`
- [x] `?` operator on Option and Result (early return)
- [x] `??` coalescing operator on Option only
- [x] `?? return`, `?? break`, `?? continue` exits
- [x] Methods: `.is_some()`, `.is_none()`, `.is_ok()`, `.is_err()`, `.ok()`, `.unwrap()`
- [x] Unused-Result diagnostic and rule
- [x] Core library Result wrappers and Errno struct
- [x] E1c raw-result convention conversion (sys.is_error)
- [x] Hooks for printing (nl_print_text, nl_print_newline, expect fail hooks)

## Stage-0 implementation reference

**Type creation and interning (checker.rs, typed.rs):**
- `option_type()` at checker.rs:6309 — creates Option<T> instances
- `check_builtin_constructor()` at checker.rs:6438–6530 — handles `some(x)`, `none`, `ok(x)`, `err(x)`
  - `some`: 6446, infers or expects Option type
  - `none`: 6480, yields Option from context
  - `ok`/`err`: 6500–6530, infers or expects Result type
- Interning during checking: inferred types from constructor arguments (6244–6285)
- `.ok()` method synthesizes Option at checker.rs:8415

**Try operator lowering (checker.rs, emit.rs):**
- Checker: checker.rs:6023 (`ExprKind::Try` matched), 11221–11277 (typed Try node created)
- Unused-Result rule: `require_handled_result()` at checker.rs:3872–3900
  - Callers at 4710, 5319, 5369, 5591, 5746 (statements and tails)
  - Diagnostic text: "this collection operation returns a Result...; handle it with '?'" (updated by PLAN small fix)
- Emission: `emit_try()` at emit.rs:18713, `emit_try_from_storage()` at 18734, `emit_try_to()` at 18838
  - Lowers to branch on tag, copies error to hidden destination, returns with enclosing type's layout (18774–18836)

**Methods and equality (checker.rs, emit.rs):**
- `check_method_call()` at checker.rs:6533 — routes to typed handling (typed.rs lines depend on kind)
- Methods on Option/Result: `.is_some()`, `.is_none()`, `.is_ok()`, `.is_err()`, `.unwrap()`, `.ok()`
  - Checked at checker.rs:10047–10576 (unqualified names)
- Unwrap failure: kinds 14 (unwrap on none) and 15 (unwrap on err) at emit.rs:22601
- Equality: emit.rs:16865 calls `emit_equal_storage()` for two operands

**Printing hooks:**
- `emit_print_value()` at emit.rs:17257–17363
- `emit_print_value_storage()` at emit.rs:17363–17466 (handles cases, payloads)
- Hooks called: `nl_print_text()`, `nl_print_newline()` at 17327, 17331
- Expectation hooks: `nl_expect_fail_header()`, `nl_expect_fail_left()`, `nl_expect_fail_right()` at emit.rs:16908–16917

**Coalesce operator (`??`):**
- Parser: parses `BinaryCoalesce` (ast.rs)
- Checker: checker.rs:6179 (`ExprKind::Try(value)` for value fallback), rejected on Result
- Emission: branch on tag, evaluate fallback on `none` (emit.rs:1681, 4504, 7452)

## Selfhost compiler interfaces (E2i ownership)

**Type kinds:** Already defined in selfhost/compiler.nl:26–38
- `TYPE_KIND_OPTION: 6L`, `TYPE_KIND_RESULT: 7L` already present
- E2c adds branches wherever `type_kind(ty) == TYPE_KIND_OPTION` or `== TYPE_KIND_RESULT`

**Type kind classification:** `type_kind()` function in selfhost, branches added for Option/Result handling

**Storage locations (E2i interface):** Already defined in compiler.nl:40–42
- E2c uses `LOCATION_NATIVE: 0L` (native slots for all E2c values)
- Location argument passing: through helper registry (HELPER_COPY, HELPER_EQUAL, HELPER_PRINT)

**Helper registry (E2i interface):** Already in compiler.nl:44–48
- E2c registers enum/Option/Result emitters (HELPER_COPY, HELPER_EQUAL, HELPER_PRINT for sum types)
- No new helpers; E2b's enum helpers serve both enums and Option/Result

**Exit and cleanup (E2i interface):** Already in compiler.nl:50–57
- E2c calls exit function for `? return`, `?? return`, `?? break`, `?? continue`
- Registers: EXIT_RETURN (1L), EXIT_BREAK (5L), EXIT_CONTINUE (6L) already defined
- `emit_exit()` in selfhost takes exit kind; E2c adds Try-exit calls (no cleanup yet)

**Signatures (E2i/E2b/E2c shared):** selfhost/compiler.nl `register_package_declarations()`
- E2c modifies to accept Result parameter types and returns (E2b handles enums)

**Hooks:** selfhost, hook table in compiler.nl
- E2c adds: `nl_print_text`, `nl_print_newline`, `nl_expect_fail_header`, `nl_expect_fail_left`, `nl_expect_fail_right`
- Each hook has C signature (name, arg types, return type)

## Test packages moving to buildable

| Package | Current class | Expected class | Notes |
| --- | --- | --- | --- |
| tests/e2/enum_* (all) | unsupported | build | E2b adds, will pass with E2c methods |
| tests/e2/option_* (Option construction, methods) | unsupported | build | E2c core |
| tests/e2/result_* (Result construction, `?`) | unsupported | build | E2c core |
| tests/e2/coalesce_* (`??` operator) | unsupported | build | E2c core |
| tests/e2/*_hook* (print/expect hooks) | unsupported | build | E2c runtime |
| Any test with Errno wrapping | unsupported | diagnose initially | Needs core library update |

Tests using `Option` or `Result` that depend on E3's features (collections, text) stay unsupported until those land.

## Pitfalls from reviews (Sol E2 findings relevant to E2c)

1. **P1 — Inferred types gate eligibility (Sol E2-r1 finding 1):**
   - `let x = some(s)` with no annotation can exceed 4096 bytes when s is large
   - `.ok()` on Result<T, E> synthesizes Option<T> at the call site
   - Layout table can't be complete after declarations; instances interned during checking must get layouts too
   - E2c must intern Option/Result instances as they're created in check_expr and synthesized (ok(), nested constructors)

2. **P1 — Pointer argument snapshot rule (Sol E2-r1 finding 3):**
   - `f(s, { s.x = 9; 0 })` must snapshot the first argument before the mutation
   - Result payload passing through `?` must snapshot the operand's tag at evaluation time
   - E2c's Try lowering must capture operand value before later arguments are evaluated

3. **P2 — Oversized sum gate is transitive (Sol E2-r1 finding 4):**
   - A 4,100-byte struct in an Option is unsupported, not the Option itself
   - E2c must check Option<T> size using E2's saturation rule (cap at 4097 during eligibility check)

4. **P1 — Default evaluation phase (Sol E2-r1 finding 6):**
   - Defaults checked before function bodies; a struct default can call any function
   - E2c result wrappers (Errno struct) may be referenced in defaults
   - Ensure phase ordering: struct declarations, then defaults, then bodies

5. **P2 — Stored unit (Sol E2-r1 finding 7):**
   - Unit payloads (`some(())`, `ok(())`, `err(())`) store nothing
   - Tag still present, but active case's unit payload takes no bytes
   - E2c must handle Option<()> and Result<T, ()> with no payload storage

## Ambiguities and open questions for manager

1. **Coalesce fallback types:** Can `e ?? return` and `e ?? break` have aggregate fallback values, or must they be scalars/never?
   - Affects unwrap-like methods: `x.unwrap_or(default)` not in E2c, but `x ?? default` with aggregate default should work

2. **Method call order vs pattern matching:** Should `x?.method()` fail as unsupported in E2c (no optional chaining), or as missing method in a later step?
   - Currently unsupported; don't add it to E2c. Confirmed.

3. **Wrapper audit:** E2c's requirement that "only wrappers make raw fallible calls" — should we scan core library code before E2c lands to ensure compliance, or accept this as an E3 audit?
   - Manager decision: E2c delivers the rule; core library update happens within E2c (Errno struct, wrappers for each sys call)

4. **Print order for nested errors:** When printing a deeply nested Result in an error path (`some(ok(err(Errno { ... })))`), is printing the innermost error case correct, or should we short-circuit?
   - Stage 0 prints the full nesting; E2c matches it byte for byte

5. **Method dispatch on Outer.Inner:** Can `option.ok()` where option is `Option<Result<T, E>>` return the nested Result, or does `.ok()` only work on top-level Results?
   - Syntax: `option.ok()` where option: Option<T> returns Option<T> (no nesting); T itself might be Result

## Next steps for implementer

1. **Enums must land first (E2b):** Option and Result are sum types; E2c reuses E2b's enum layout, copying, comparison, and printing
2. **Check E2i interfaces are stable:** All 5 interfaces must be in place and owned correctly before E2c edits shared code
3. **Core library wrappers:** Create Errno struct and write wrappers for sys.write, sys.map, sys.protect, sys.ioctl, sys.statx, sys.sigaction, sys.openat, sys.close
4. **Hooks:** Register 5 new hooks with C runtime and test contract fixtures (print_text, print_newline, expect_fail_header, expect_fail_left, expect_fail_right)
5. **Tests:** Classify e2 packages; update any that use Option/Result to build; add fixtures for each error message and feature combination

## Manager answers (Claude, 2026-10-26)

- **One rule for semantic questions:** what valid programs do is whatever stage 0 does. Answers above marked as stage-0 behaviour (nested printing, `.ok()` typing, `??` fallback types) are the prep agent's reading; confirm each with a small probe package run through stage 0 (`nlc run`) before relying on it, and pin it with a fixture.
- **Errors:** only rejection with real error text is required (Checker order in the E2 spec, `same_rejection` in the harness); no need to match stage 0's first error or wording.
- **Wrapper audit (question 3):** E2c does it, as the spec says: the core library's raw fallible calls move behind wrappers within E2c, and the audit test lands with it.
- **`?.` (question 2):** stays unsupported in E2c (E3b).
