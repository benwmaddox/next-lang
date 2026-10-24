# Round 13: `docs/DESIGN.md`

Reviewed the full current design and both round 12 reviews. Two wording contradictions remain. The fixes below preserve the recorded decisions; no additional design decision blocks first steps 1–2.

## 1. “Whole state” still claims startup reservation

**Memory / Why a state tree, line 80; compare Who owns state, Static allocation, and Decided.** The sentence says the whole state's size is known, “reserves it once at start,” and never moves. But locals are state too (line 57), and the later rules put local values on job stacks, reserve them per job, commit them as used, and include them in admission (the memory check deciding whether another job fits; lines 119, 141, 152; Decided line 576). This reintroduces the R12 startup-versus-local accounting conflict.

Replace it with:

> **Every state's maximum size is in its type.** Declared capacities and field maxima let the compiler calculate each value's bound. Program and shared globals are reserved at startup and never move. Locals have fixed bounds on job stacks; the stacks are reserved per entry point (the function that starts a job) and committed as used, and local values count toward per-job admission.

**Acceptance:** `inspect memory` reports global startup claims separately from per-entry-point stack bounds; a large local collection contributes to its job's stack reservation and admission, not the startup claim.

## 2. Bounded collections are still called nested growing values

**Databases / Query results are bounded, line 198; Threads and data stacks / How the compiler assigns stacks, worked-example comment at lines 256–258.** Collections says bounded collections are fixed-size ordinary values (line 86), and the loop rules explicitly say `list<Ascii max 40, 100>` is not a growing value (line 294). Yet the database text says any list holding text is nested-growing, and the render comment says `List<Row>` with bounded `Ascii max 60` is refused. That contradicts the collection and stack rules and makes the renderer example suggest an unsupported restriction.

In the database section, replace the restriction with:

> A query with `limit N` may produce a bounded `list<Row, N>` when every variable-size field in `Row` has a declared maximum. Its capacity and field maxima give the result's byte bound; it may contain bounded `Text`, `Ascii` or `Bytes`. Rows may also be streamed one at a time. A container whose elements grow without their own bounds remains a nested growing value and is refused in v1.

In the render comment, replace the refusal with:

> A bounded `list<Row, 500>` is legal; `view Row` avoids copying the rows.

**Database acceptance (when database support is implemented):** a limited query can return bounded text rows within the computed result bound. **Step 2 acceptance:** the render example accepts both the view and bounded list forms, while still refusing an unbounded growing container.

## Other sections

The old table terminology is explicitly mapped to `pool`; database `limit N` is a per-query result bound, not a table row maximum; the no-compaction and free-list rules agree with the snapshot and reservation sections.

**Later:** No new item. Database support and nested growing values are already listed in `docs/DESIGN.md`.

**Questions:** None.
