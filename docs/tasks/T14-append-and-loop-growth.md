# T14: append mode, iteration scopes and loop growth (milestone M3, part 2)

Depends on T13. Same rules. Read DESIGN.md "How the compiler assigns stacks" (both output contracts and the worked example) and "Loops can't quietly fill a stack".

## Append mode

- When a call's result goes straight into a builder (`out += line(r)`, or `out.append(line(r))`), the callee runs in **append mode**: a hidden grow parameter for the builder plus its remaining capacity; it writes its result past the builder's end and returns the length written; on success the caller moves the builder's end; on failure the builder's end and stack top go back. A function that can't run in append mode (it reads the builder, say) gets its result built on scratch and copied. The overlap check covers the hidden builder like any parameter: `out += f(out)` evaluates `f(out)` into separate scratch and finishes reading before the append starts, or is refused.
- The worked example in DESIGN.md (`render`/`line`) must compile with exactly the contracts the doc gives (N = 2; `line` writes onto `out`'s end; `ascii_upper`'s temporary on stack 1) and print the expected output; its byte bounds (40,000 for `render`) must come out of the checker.

## Iteration scopes and loop growth (DESIGN.md "Loops can't quietly fill a stack")

- Every iteration is a scope: the body's temporaries are freed at the iteration's end and on `continue`/`break`, while stacks of values that live outside the loop keep the end they've grown to.
- `s = s + piece` on an outer value compiles to an append in place; any other reassignment of an outer growing value (`acc = merge(acc, x)`) builds on scratch and copies down, with the two-value peak counted.
- **A value a loop keeps growing must have a bound** the checker can show: its type's maximum, or a counted loop over a bounded input with bounded growth per iteration. Otherwise a build error naming the value and the loop and offering both fixes.
- `expect stack_peak(f) < 2 MB`-style tests are T16 (with `inspect stacks`).

## Acceptance cases (DESIGN.md step 2, append and iteration parts)

- Exact output in fresh-result and append modes, at the declared maximum; capacity checked before any store; a failed append leaving no partial result.
- The worked example: output, the contracts in the report, N = 2.
- `s = s + s` (from T13) and `out += f(out)` safe or refused.
- `continue` and `break` discard the iteration's scratch and keep the outer builder; a loop running a million iterations that appends to an outer `Ascii max 1000000` one byte at a time and builds a temporary each iteration, ending with the right length.
- An unbounded loop growth (build error with both fixes named).

## Report

docs/tasks/T14-report.md.
