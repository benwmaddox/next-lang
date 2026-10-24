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
