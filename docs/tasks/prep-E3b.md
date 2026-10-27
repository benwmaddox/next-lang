# Prep brief: E3b (capacity results, pop, proven pushes, `?.`)

Status: brief for the model that writes the E3b plan. It follows docs/tasks/prep-E3a2.md. The scope is defined by docs/tasks/E3-selfhost-collections-text.md (the "Parts and order" row for E3b, "Arrays and lists", "Eligibility", "Directed fixtures").

## Scope checklist

E3b adds these, and nothing else:

- [ ] `Result<(), Full>` as a value: `?`, `match`, `unwrap`, `is_ok` and the other operations E2c already provides on `Result`.
- [ ] `push` and `insert` return `Result<(), Full>` when the list is bounded and at capacity. The list is unchanged on `Full`.
- [ ] `pop` returns `Option<T>`. An empty list gives `none`.
- [ ] Proven pushes: a push under a bound the checker can prove (for example, a loop bounded by the list's capacity) is accepted without a `Result`. Stage 0 decides which pushes are proven; the selfhost checker must match its decision.
- [ ] `discard` in full: `discard` applies to a `push`, `insert` or `pop` result, under the rules stage 0 applies. Refusals are reject fixtures.
- [ ] `Full` printing: `Full`, `err(Full)` and `ok(())`, with the same text as stage 0.
- [ ] `?.` (DESIGN, "`?.` and `??`"): the optional-chaining form flattens one `Option` level. Fixtures show `?.` on a `none` gives `none`, and on a `some` applies the field or method.
- [ ] Sum-typed elements and struct fields of elements: one lane of whole values, as in "Layout and residence".
- [ ] `write`-parameter store-back on `?`: an early return from `?` must still write back the `write` argument's final state.

Not in E3b: unbounded collections' growth (E3d2), `Ascii` and `Text` (E3c), maps and sets (E4), sum types over 4,096 bytes in regions (listed in the E3b row, so check with the manager whether it lands here or in E3a1).

## Stage-0 implementation reference

- Stage 0 is the Rust `nlc` in compiler/src, frozen at tag `stage0-2026-10-26` (release-fix tags `.1` and `.2` are recorded in docs/PLAN.md). Read its checker for: the `Result` and `Option` method table, `push`/`insert` capacity handling, the proven-push analysis, `discard`, and `?` and `?.` lowering. Stage 0 is the source of truth for expected results.
- The E3 stage-0 reference fix list in the spec applies here where it touches `Full`. The fixes are tested by their own fixtures, not by E3b's fixtures.
- Expected output is written by stage 0 on the same package, then compared with the selfhost compiler's output. A difference in the text of a `Full` or `err(Full)` message is a failure.

## Selfhost plug-in points

- The parser and checker in selfhost/*.nl: add the `?.` token and its precedence next to `??`. Check that the parser rejects `?.` on a non-option value with the same first error as stage 0.
- The type checker: the `Result<(), Full>` type is already produced by E2c's wrappers. E3b needs the method table entries for `push`, `insert`, `pop`, `discard` and the printing forms.
- The lowering: the list operations emit the capacity test and the `Full` value. The write-back for `?` must happen on every early exit path, which is the same cleanup path E2 defines for `write` parameters.
- The data-stack layout is E3a1's. E3b does not add regions; a `Full` value is a small aggregate and lives in the frame.

## Test packages moving to buildable

From tests/e1/classification.tsv, rows that stay `unsupported` until E3b and become `buildable` or `reject` when E3b lands. Confirm the exact rows against the file before the plan is final:

| Row family | Lines (approx.) | Expected change |
| --- | --- | --- |
| t06_view_pop | 296 | `unsupported` to `buildable` |
| t10_queue_pop_view | 351 | `unsupported` to `buildable` |
| Proven-push fixtures | (search for `discard`) | accepted or refused, as stage 0 decides |
| `discard` refusals | (search for `discard`) | `reject` with stage 0's text |

Rows that are reject fixtures must keep stage 0's error text. The selfhost diagnostic must match the first error only, not every error (docs/design/ or error-matching notes, as in the next-lang error matching decision).

## Pitfalls from reviews

From docs/reviews/sol-E3-r1.md, the points that apply to E3b:

- Argument exclusivity: `f(xs[0], { xs[0] = 9; 0 })` must be rejected or evaluated with the rule in the spec. A `pop` in an argument position is the same kind of case, so E3b's fixtures include `push(pop(xs))`-style forms.
- Saturated sizes: a `Full` count must not wrap. Test the largest capacity.
- Error order: when `?` and a capacity error both apply, the first error reported must match stage 0. Test a package with two errors.
- Write-back on `?`: the `write` store-back must happen on the early-return path, not only the normal one.

## Friction items for E3b

The seven friction items in the spec's "Language friction fixes" section are placed at E3c, E3d1, E3d3, E3a1 and E4. None is owned by E3b. Item 4 (a large Ascii value passed through a helper exhausts the data stack) is first exercised by `pop`, because `pop` shrinks a list while its element is still live. E3b's fixtures run that case under `NLC_TEST_STACK_FORCE_MOVE=1`, and the item stays with E3a1.

## Ambiguities and open questions

1. Sum types over 4,096 bytes in regions: E3b or E3a1? The spec's E3b row lists them, but the region work is E3a1's. The manager should pick one.
2. `pop` on a list of sum-typed elements: does the popped `Option<T>` hold its lane, or copy it out? Stage 0 decides; the plan must say which.
3. `?.` on a chain of two options: the spec says it flattens one level. Does `a?.b?.c` need a fixture that shows the second `?.` is not flattened twice?
4. The proven-push analysis: if stage 0's rule is looser than the selfhost checker's, which is the reference? The spec says stage 0 is the reference, but the rule should be written down so both compilers can be checked against it.
5. Is `Full` printed from a local or from the `Result`? This affects whether `err(Full)` needs a separate fixture.

## Next steps

1. Confirm the classification rows by reading tests/e1/classification.tsv.
2. Write the E3b plan with the scope checklist above, one fixture per bullet.
3. Run the E3b fixtures on stage 0 first; record its output as the expected result.
4. Implement in selfhost/*.nl, then compare outputs.
5. Write docs/tasks/E3b-report.md with the report list from the spec.

Do not edit compiler/src, selfhost/, compiler/tests/ or scripts/ in the planning step.

## Manager answers (Claude, 2026-10-27)

- **Sum types over 4,096 bytes:** E3b, as the spec's eligibility section says (the oversized-sum gate stays until E3b; E3a1 placed only large structs in regions).
- **Friction items in E3b:** `while`, `~`, the compound bitwise assignments, `if`/`else if` without `else` as a statement, unsuffixed literals typed from context (see the spec's "Language friction fixes"); stage 0 rejects several of them, so their fixtures are `expected` class (hand-written expected output, reviewed).
- **Ranges:** accept both `a to b` and the deprecated `a..=b` with the same meaning; the deprecation warning comes after B1, so no warning fixture now.
- **Errors:** only rejection with real error text is required; behaviour of valid programs must match stage 0 exactly.
