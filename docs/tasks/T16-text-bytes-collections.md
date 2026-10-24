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

DESIGN.md's `render`/`line` example in its runnable T15 form now uses `list<Ascii max 60, 500>`, with the contracts the doc gives and N = 2.

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

## Ben's stack-count decision (2026-10-24), overrides anything above

DESIGN.md "Few stacks, used well": **one data stack per job by default, at most two.** Where this task says "N data stacks", "fixed scratch stack", "window k = 1 on stack 1" or "N = 2", read it under these rules:

- Finished values share the current stack in last-in-first-out order; only a value still growing while something above it is alive must be on top.
- There is **no separate fixed-scratch stack**: a large fixed-size temporary goes on top of the current data stack when nothing below it will grow during its lifetime, otherwise on the native stack.
- **Build above, then slide down:** something built while a value below it is still growing is built just past that value's end, then moved down onto it. A second data stack is very rare: used only when such a piece could exceed 64 KB (Ben, 2026-10-24), flagged as a warning in `inspect stacks`; never more than two. Append mode writes straight onto the growing value's end and needs no temporary at all.
- The worked example (`render`/`line`) runs on **one stack, N = 1**: `name` and `line`'s result are built above `out`'s end and the result slides down. Its worst case is 40,000 + 60 + 80 = 40,140 bytes plus page rounding (T17's numbers).
- `inspect contracts` / `inspect stacks` list every slide-down site and its worst-case copy size.
