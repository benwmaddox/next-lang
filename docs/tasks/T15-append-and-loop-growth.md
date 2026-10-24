# T15: append mode, iteration scopes and loop growth (milestone M3, part 3)

Depends on T14. Same rules. Rewritten for the reserve-ahead decision, folding in sol-T13-T14-r1, sol-M3-r2 and sol-fewstacks-r1. Read DESIGN.md "How the compiler places values" (the append contract) and "Loops can't quietly fill a stack".

## Append mode

- When a call's result goes straight into a builder (`out += line(r)`), the callee runs in **append mode**: it gets the builder's region, its **accepted length** (what's already part of the value), and its remaining capacity; it writes past the accepted length and returns how much it wrote. The caller publishes the new length only on success. The accepted length is separate from the physical top of the stack, which also covers temporaries placed above.
- **Checkpoints:** each append first saves the builder's length (and for text later, its code-point count) and the stack top. A failure, whether `Full` or an `err` from a fallible producer (one returning `Result<Ascii max N, E>`, whose error reaches the caller as an `err`, distinct from `Full`), restores the checkpoint, even after part of the output was written. Nested appends (`out += f()` where `f` does `piece += g()`) each restore their own checkpoint, so an inner success disappears if an outer step then fails.
- A function compiled for both result modes publishes both contracts. Function types (T11) record whether a function supports append mode; an indirect call uses it only when every function that fits the type does.
- The builder is an argument for the overlap check: `out += f(out)` builds `f(out)` in a temporary region first, or is refused.

## Loops

- Every iteration is a scope: its temporaries are freed when it ends and on `continue`, `break`, `return` and `?`; a builder outside the loop keeps the length it's grown to inside its reserved region, and the top returns to where the iteration started (above that region). A failed append restores its own checkpoint first.
- `s = s + piece` on an outer value is an append in place when `piece` doesn't read `s`; otherwise T14's safe path applies. Any other reassignment of an outer growing value (`acc = merge(acc, x)`) builds in a temporary region and copies into `acc`'s region, with the two-value peak counted.
- **A value a loop keeps growing must have a bound** the checker shows: the type's maximum (with `try_append`), or for a plain `+=`, a proof (a counted loop over a bounded input, bounded growth each iteration). An `Ascii.empty()` whose maximum can't be inferred is a build error naming the value and the loop, with both fixes.

## The runnable worked example

DESIGN.md's `render`/`line` uses `Ascii` fields in state and shared snapshots, which aren't ready, so this equivalent stands in (the collection version is T16's):

```
fn render(n: int 0..=500) -> Ascii max 40000 {
    var out = Ascii.empty()                   // in the caller's 40,000-byte destination region
    for i in 0..n { out += line(i) }          // append mode: line writes into out's region
    out
}
fn line(i: int 0..=499) -> Ascii max 80 {
    let name = label(i)                       // a temporary placed above out's region
    name + ": " + str(i * 7)                  // streamed into out's region
}
fn label(i: int 0..=499) -> Ascii max 60 { ascii_upper("row") + str(i) }
```

Expected: one data stack, no copies of lines; the stack's worst case is 40,000 (the destination region) plus `name`'s 60 bytes plus descriptors and alignment; `inspect contracts` shows `line` in append mode with a requirement of about 60 bytes above `out`'s region, and `label` and `ascii_upper` writing into their destinations.

## Acceptance cases

- Exact output in fresh-result and append modes at the declared maximum; capacity checked before any store; a failed append leaving no partial output.
- Nested appends: an inner success followed by an outer failure (all rolled back); a producer error after a prefix (rolled back, error returned); reuse of the builder after a rollback.
- The example above: output, contracts, worst case.
- `out += f(out)` safe or refused; `acc = merge(acc, x)`'s copy with its peak.
- A loop appending one byte at a time to an outer `Ascii max 1000000` a million times, building a temporary each iteration: right final length; measured peak stays bounded.
- An uninferable builder in a loop (build error naming both fixes).
- Three interleaved builders appended to in turn inside a loop, including through a function value.

## Report

docs/tasks/T15-report.md.

## Corrections from Sol's third M3 review (docs/reviews/sol-M3-r3.md), binding

- **Fallible appends, concretely.** A producer that can fail returns a `Result`; appending it is written with `?` or handled explicitly:

  ```
  fn field(raw: Ascii max 40) -> Result<Ascii max 40, ParseError> { ... }

  fn row(a: Ascii max 40, b: Ascii max 40) -> Result<Ascii max 100, ParseError> {
      var out = Ascii.empty()
      out += field(a)?             // append mode; on err, out is rolled back and the error returned
      out += ","                   // proven to fit: plain +=
      out += field(b)?
      ok(out)
  }

  fn log_line(buf: grow Ascii max 4096, x: Ascii max 40) -> Result<(), Full> {
      buf.try_append(field(x) ?? return ok(()))   // a capacity error is Full; a parse error is handled by ??
  }
  ```

  - `out += producer()?` with capacity proven: the producer runs in append mode; on its `err`, the checkpoint is restored and `?` returns the error. With capacity not proven, `out.try_append(producer()?)` returns `Full` on capacity, with the checkpoint restored.
  - When the producer's error type is itself `Full`, the two are told apart by where they come from: `?` on the producer's result passes its `Full` up; `try_append`'s own `Full` is its return value.
  - Append mode replaces T14's evaluate-first path whenever the producer supports append mode; otherwise T14's path stays.
  - Tests: a producer writing a prefix then failing (rolled back, error returned), then a successful reuse of the builder; the same with `try_append` failing on capacity after a prefix; `E = Full`.
