# T16: Text, Bytes and growing values in collections (milestone M3, part 4)

Depends on T15. Same rules. Read DESIGN.md "Text, ASCII and bytes", "Variable-size fields" (inline small fields and size classes), "Bounds" (the reservation arithmetic), and "One declaration, every layer" (code-point lengths).

## Text and Bytes

- `Text max N`: always valid UTF-8; `N` counts code points, so its byte bound is 4N. `Bytes max N`: raw bytes, `N` bytes. `Ascii` passes to a **read** `Text` parameter free; a write or grow `Text` parameter needs an `Ascii` parameter, a proof, or a checked conversion (DESIGN.md). `Bytes` to `Text` and `Text` to `Ascii` are checked (`Result`); `.bytes()` views text as bytes.
- Operations as for `Ascii` (T14, T15), with `len()` counting code points for `Text` (and `byte_len()`), comparisons by code point order (bytewise for valid UTF-8), slicing by code-point index (`s.slice(a..b)`) and by byte offset only on `Bytes`. The full Unicode `upper`, with its contract of at most 3 times the input's code points; `ascii_upper` stays.
- Literals are `Text` when not ASCII (`"ß"`), `Ascii` when they are; a context can make an ASCII literal `Text`.

## Growing values in collections (size classes, no compaction)

- Collections may now hold `Ascii`, `Text` and `Bytes` fields and elements: `list<Ascii max 60, 500>`, `pool<Message, 1000>` with `body: Text max 2000`.
- Layout per DESIGN.md: a field whose maximum is 64 bytes or less sits inline at full size with its length; a larger one uses size classes (128, 256, 512 bytes and so on, up to the class holding the maximum), each an array of equal slots with a free list, the field holding `{class, slot, length}`. Writing a value that fits its slot writes in place; one needing another class takes a slot there and frees the old one. Nothing moves. Reservation: under twice the largest class per element per field, plus the inline parts.
- Views: replacing a variable-size field under a live view of it is a build error; removing an element frees its slots.
- Reading a growing field copies it onto a data stack (bounded by the field's maximum), or passes a read-only view without copying.

## The worked example

DESIGN.md's `render`/`line` example in its runnable T15 form now uses `list<Ascii max 60, 500>`, with the contracts DESIGN.md gives: one data stack, `out` in the caller's reserved 40,000-byte region, `name` placed above it, lines streamed in with no copies.

## Acceptance cases

- `Text`: code-point lengths with characters outside the basic plane; a 4-byte character at the declared maximum; invalid UTF-8 from `Bytes` giving an error; `Ascii` to read `Text` free (no copy in the IR), to write `Text` refused without a conversion; `upper("ß")` giving `"SS"` within its contract.
- Size classes: a text moving to a larger class and back, freeing its slot each time; with the collection at capacity, moving fields across classes always succeeds and a freed slot is reused at once; no other element's bytes move (check by address in a test hook); removing an element frees its slots.
- A field write under a live view of that field (build error).
- The worked example's output and contracts.

## Report

docs/tasks/T16-report.md.

## Corrections from Sol's second M3 review (docs/reviews/sol-M3-r2.md), binding

- Also: `Text bytes max N` (a byte budget on text) and a checked `Bytes` to `Ascii` conversion. Appends enforce both the code-point and the byte limit; a `write Text` change that keeps its code-point length can still need more bytes, and is checked.
- Slices: `s.slice(a..b)` is a copy onto a data stack (bounded by the source's maximum); an out-of-range or non-boundary index fails at its line. `.bytes()` is a temporary read-only view, usable as an argument, never stored, returned or written through.
- **Field updates are failure-safe:** a write that would exceed a field's maximum returns a handled error (`Full`) and leaves storage untouched; the new bytes are written into a fresh slot and validated before the descriptor is switched and the old slot freed, including when several fields are replaced at once.
- A value that shrinks stays in its current slot (DESIGN.md allows this); it doesn't move back to a smaller class. Change the acceptance case accordingly.
- View protection covers the collection and everything enclosing the viewed element, including indirect calls (T11), removal and shifting.
- Size accounting counts descriptors, lengths, free lists, flags, alignment and every enclosing capacity; overflow in the multiplication, class rounding or page rounding is a build error.
- Copies of collections holding text copy the bytes, so a copy never depends on its source's slot arrays. Genuinely nested growing values (an unbounded list of texts) stay refused; bounded collections of bounded text are allowed. A local collection's push never moves a stack top.
- More cases: nested collections of text; a copy surviving its source's cleanup; sorting a list of `Ascii` (with T12's built-in extended to `Ascii` by bytewise order); `Ascii` keys in maps and sets (T09's built-in extended).


## Corrections from Sol's third M3 review (docs/reviews/sol-M3-r3.md), binding; they override the bullets above where they differ

- **Failure-safe updates by staging:** a field update first writes and validates the new bytes in temporary storage on the data stack (counted in the bounds); then, if the new value fits the field's current slot (or its inline space), it's copied into that slot; only if it needs another class is a slot taken there and the old one freed. So a same-class replacement works even when every element of a full collection is in that class. A multi-field replacement stages every field before publishing any. Tests: a same-class replacement at capacity; an inline-field replacement; a replacement whose later field fails, leaving every old field intact.
- **The worked example fixture, complete:**

  ```
  struct Row { name: Ascii max 60, count: int 0..=999999 }
  fn render(rows: list<Row, 500>) -> Ascii max 40000 {       // rows is a read parameter: borrowed, not copied
      var out = Ascii.empty()
      for r in rows { out += line(r) }
      out
  }
  fn line(r: Row) -> Ascii max 80 {
      let name = ascii_upper(r.name)
      name + ": " + str(r.count)
  }
  fn main() {
      var rows: list<Row, 500> = list {}
      for i in 0..500 { discard rows.push(Row { name: "row" + str(i), count: i }) }
      print(render(rows).len())
  }
  ```

  The rendering requirement above the caller-owned input is 40,000 (the result region) + 60 (`name`) + descriptors and alignment; the entry point's total also counts the `rows` list's own region in `main`.
- The shrink and view acceptance cases above are replaced by this section's rules and the earlier correction (a shrinking value stays in its slot; view protection covers enclosing values).
