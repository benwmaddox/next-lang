# T15: append mode, iteration scopes and loop growth (milestone M3, part 3)

Depends on T14. Same rules. Binding points from docs/reviews/sol-T13-T14-r1.md. Read DESIGN.md "How the compiler assigns stacks" (the append contract) and "Loops can't quietly fill a stack".

## Append mode

- When a call's result goes straight into a builder (`out += line(r)`), the callee runs in **append mode**: a hidden grow parameter for the builder plus its remaining capacity; it writes past the builder's end and returns the length written; on success the caller moves the end; on failure the end and top go back. A function compiled for both modes gets both contracts, and its published window is the larger. A fallible producer (one returning `Result<Ascii max N, E>`) in append mode reports failure and leaves the builder unchanged.
- The hidden builder is an argument for the overlap check: `out += f(out)` evaluates `f(out)` into separate scratch first, or is refused.
- Function types (T11) record whether a function supports append mode, and indirect calls use it only when every function that fits the type does.

## Loop growth

- An outer value grown in a loop keeps its end across iterations while the iteration's own scratch is reset (DESIGN.md). `s = s + piece` on an outer value is an append in place; any other reassignment of an outer growing value (`acc = merge(acc, x)`) builds on scratch and copies down, with the two-value peak counted.
- **A value a loop keeps growing must have a bound** the checker shows: the type's maximum suffices for `try_append`; a plain `+=` in a loop needs a proof (a counted loop over a bounded input, with bounded growth each iteration). An `Ascii.empty()` builder whose maximum can't be inferred is a build error naming the value and the loop, with both fixes.

## The worked example

DESIGN.md's `render`/`line` example needs `Ascii` fields in state and shared snapshots, which aren't ready, so it's deferred. Instead, this runnable equivalent must compile with the contracts DESIGN.md gives and print the right output:

```
fn render(names: list<Ascii max 60, 500>, counts: list<int 0..=999999, 500>) -> Ascii max 40000 {
    var out = Ascii.empty()                        // its maximum: from the result type
    for i in 0..names.count() {
        out += line(names[i], counts[i])           // append mode
    }
    out
}
fn line(name: Ascii max 60, count: int 0..=999999) -> Ascii max 80 {
    ascii_upper(name) + ": " + str(count)          // streamed into the destination
}
```

(`list<Ascii max 60, 500>` needs growing values in collections, T16; until then, use two parallel arrays of fixed `Ascii max 60` read parameters supplied by a helper, or move this fixture to T16. Expected contracts: `render` and `line` have scratch window `k = 1`; `ascii_upper` and `str` have `k = 0`, excluding their caller-owned destinations; with destination 0 and base 1, N = 2.)

## Acceptance cases

- Exact output in fresh-result and append modes at the declared maximum; capacity checked before any store; a failed append leaving no partial output.
- The example above: its output, its contracts from `inspect contracts`, N = 2.
- `out += f(out)` safe or refused; `acc = merge(acc, x)`'s copy-down with its peak.
- A loop appending one byte at a time to an outer `Ascii max 1000000` a million times, building a temporary each iteration: right final length, no exhaustion.
- An uninferable builder in a loop (build error naming both fixes).

## Report

docs/tasks/T15-report.md.

## Corrections from Sol's second M3 review (docs/reviews/sol-M3-r2.md), binding

- **The fixture:** T15's runnable stand-in uses a counted loop over integers, not collections of `Ascii` (which are T16):

  ```
  fn render(n: int 0..=500) -> Ascii max 40000 {
      var out = Ascii.empty()
      for i in 0..n { out += line(i) }
      out
  }
  fn line(i: int 0..=499) -> Ascii max 80 {
      let name = ascii_upper(label(i))        // a real temporary on stack 1, as in DESIGN.md
      name + ": " + str(i * 7)
  }
  fn label(i: int 0..=499) -> Ascii max 60 { "row" + str(i) }
  ```

  Keep DESIGN.md's explicit `let name = ascii_upper(...)` so the temporary exists and `k = 1`; the collection version of the example is T16's.
- Append-mode failure: a fallible producer returns its error to the caller as an `err`, distinct from `Full`; in both cases the builder is rolled back even after a prefix was written. Test both.
- `s = s + piece` becomes an in-place append only when `piece` doesn't read `s`; otherwise T14's overlap handling applies.
- Function types carry each function's byte bounds per stack (not only its window and append flag), and calls through function values take the maximum over every function that fits; T17 relies on this.
