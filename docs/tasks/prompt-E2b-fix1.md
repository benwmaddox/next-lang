You are the implementer (Luna) for next-lang, in /mnt/d/code/next-lang. Claude is the manager and reviewer.

This is a fix round for E2b (enums, `match`; commit a5c0b3a) and E2c (`Option`/`Result`, `?`, `??`; read docs/tasks/E2c-report.md), from Sol's review docs/reviews/sol-E2b-r1.md. Sol's probe sources and results are under /tmp/sol-e2b-probes/ (if missing, the review quotes each probe in full). Fix all five findings in the self-hosted compiler, and check each one against E2c's built-in constructors too (`none`, `some(x)`, `ok(x)`, `err(e)`), since they share the constructor and name-resolution paths:

1. Nullary enum values (qualified `E.A` and bare `A`, and `none`) in struct literals, nested struct literals, constructor payloads and defaults: use the shared aggregate-source classification (`aggregate_source_kind`/`aggregate_source_id`) instead of the duplicated one around compiler.nl's struct-field initialisation.
2. A constructor payload that terminates (`E.C(return 6)`, `continue`, `break`, and `some(return x)`, `?` inside a payload): propagate termination; emit nothing after the exit.
3. Name resolution for calls: visible locals, parameters and match bindings first (a non-callable local named like a case is rejected, as stage 0 rejects it), then functions, then cases, as stage 0's `ExprKind::Name`/call paths do.
4. Helper discovery classifies resolved calls the same way checking and emission do: a case spelled like a built-in (`print`, `some`, ...) still registers its payload's copy helper.
5. Compile time: no quadratic name lookup per constructor; keep stable type ids and an indexed lookup. Add a scaling check (many distinct small enums, e.g. 6,400 as in Sol's generator) to the existing performance tests, with a bound that fails on super-linear growth.

Each finding gets a fixture (valid ones as build class with stage-0 output, the shadowing one as diagnose). Errors need not match stage 0's wording or order. Stage 0 is frozen. Always CARGO_TARGET_DIR=$HOME/.cache/next-lang/target; large builds under `ulimit -v 8000000` and `timeout`. Acceptance: both full suites, `cargo fmt --all -- --check`, the selfhost_interfaces test, the comparison in default and `NLC_LONG_TESTS=1` modes at zero mismatches, `git diff --check`. Delete scratch dirs you create.

Rules: never commit, branch, stash or reset; never edit docs/DESIGN.md, docs/PLAN.md, docs/research/ or docs/reviews/. Write docs/tasks/E2b-fix1-report.md: each finding, the fix, its fixtures, and the scaling numbers before and after.
