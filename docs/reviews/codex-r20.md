# Round 20 review

Examples label their syntax proposals; syntax gaps are not settled-rule violations. Citations link to [DESIGN.md](../DESIGN.md). `Option` means value-or-absence; `Result` means success-or-error.

## Rule violations and main findings

- **Bytes to Ascii is a `Result`, not an `Option`.** `to_ascii() ?? return none` conflicts with the checked-conversion rule and `??` only handles `Option` ([Text](../DESIGN.md#L544), [`??`](../DESIGN.md#L512)). Correct it as:

  ```
  let ascii_path = match path.to_ascii() { ok(p) => p, err(_) => return none }
  ```

- **`?? continue` is not in the stated syntax.** Current `??` allows a default or `return`, not `continue` ([DESIGN line 512](../DESIGN.md#L512)); use `match` with `none => continue` or specify the extension.
- **Rocks splitting wastes a freed slot.** Adding children before removing the hit parent means a full pool drops both, although one slot is about to open ([example](../EXAMPLES.md#L109)). `let r` makes a local value copy ([DESIGN line 277](../DESIGN.md#L277)), so remove before splitting:

  ```
  let r = match g.rocks.get(rid) { some(r) => r, none => continue }
  g.score = g.score + (long)(points(r.size))
  g.rocks.remove(rid)
  split(g, r)
  ```

  Put `if r.size <= 1 { return }` inside `split`; its cast relies on a caller refinement not in the callee's input ([rules](../DESIGN.md#L559)). `ttl == 0` is also checked after moving, so a 60-tick bullet moves on creation and once after reaching zero; expire it before that move.
- **The game is incomplete.** `spawn_wave` is undefined, and the described lives/game-over behavior has no ship collision path ([game](../EXAMPLES.md#L40)). Define these or label the omissions. Whether `for r in g.rocks` is a writable view is also unstated ([DESIGN line 284](../DESIGN.md#L284)).
- **logsum does not select the busiest paths.** Its map keeps the first 20,000 distinct paths and drops later new keys; `top_by_value(20)` ranks only those ([example](../EXAMPLES.md#L190)). Rename the claim or use a bounded approximation of the most frequent paths, then test a late frequent path. `lines` includes malformed records, while `errors` only counts parsed statuses; track parsed responses for the stated error-response percentage. Specify how read errors after `open` map to `ToolError` or fail the job.
- **The rate limiter under-refills and lacks eviction.** Each successful sub-second request resets `refilled`, losing fractional time. A pre-queue timestamp can produce negative tokens and fail the checked cast; take time when the writer applies the update, from a clock that cannot move backward, and retain the fraction. After 100,000 addresses, new ones are denied indefinitely. Elapsed-time clock design is open ([example](../EXAMPLES.md#L322), [DESIGN](../DESIGN.md#L824)).
- **The JSON shape has no `sent` field source.** `MessageOut` reads `m.sent`, but `Message` and its inserts define no such field ([EXAMPLES](../EXAMPLES.md#L347), [chat model](../DESIGN.md#L44)). Add and populate `sent: Time`, or remove it from the response. `Message.Key.max` as the initial cursor excludes a row with the maximum key; branch on `before == none` and omit that predicate ([key range](../DESIGN.md#L304)). The 429 mapping also promises `Retry-After`, but returns only `HttpStatus`; specify a response/header result.
- **CRC-32 and Rocks' score are correct.** Independent checks give `400 // 3 == 133` and `zlib.crc32(b"123456789") == 0xcbf43926`. Loops appear to include the start and exclude the end; state this and distinguish it from inclusive refinement bounds such as `int 0..60`.

Affirmatives: no closure violation—query predicates and scoped blocks are allowed ([DESIGN](../DESIGN.md#L533)); effects (outside actions like I/O) are inferred, so annotations are unnecessary ([line 612](../DESIGN.md#L612)). Spawn I/O jobs; parallel-loop bodies are effect-free ([line 424](../DESIGN.md#L424)). CRC's index is `long`. Score overflow stops the game tick; use `checked_add` if it should survive ([line 720](../DESIGN.md#L720)).

## Open-point audit

- **Rocks:** mode spelling is a real syntax gap ([DESIGN line 350](../DESIGN.md#L350)); whether proven pushes may skip `Result` is decided, but the compiler must prove these limits on the number of ids or the example must handle errors ([line 202](../DESIGN.md#L202)); writable loop views are partial ([line 284](../DESIGN.md#L284)); pool reset/generation behavior remains open ([line 824](../DESIGN.md#L824)).
- **logsum:** I/O jobs, suspension and admission are addressed ([lines 320–327](../DESIGN.md#L320)); exact `spawn` result, error and capability-lifetime rules remain open. Bounded copies and frozen pools are described ([lines 224, 444](../DESIGN.md#L224)), but handing a builder to a spawned job is not; specified handoff is to parallel-loop chunks ([line 450](../DESIGN.md#L450)). `?` error conversion is explicitly open ([line 803](../DESIGN.md#L803)); tuples are not specified (use a named record meanwhile). `try_as` returning `Option` needs a declared contract.
- **Server:** one writer for shared state is decided, but per-worker copies and how jobs reach them are not defined; a plain global has one home worker ([line 223](../DESIGN.md#L223)). Latest-version decisions and all-or-nothing publication are decided ([line 330](../DESIGN.md#L330)); transaction return values and `?` abort semantics remain gaps. Whether `return` inside a scoped block leaves the enclosing function is also unspecified ([line 533](../DESIGN.md#L533)). `api` versus `action` is open; only page/action forms are described ([line 705](../DESIGN.md#L705)).
- **CRC:** explicit widening casts are required; a shorter *explicit* spelling such as `b.u32` is optional syntax, not an implicit-conversion exception ([line 519](../DESIGN.md#L519)). Indexes are `long`, but range-type inference is not defined ([lines 504, 524](../DESIGN.md#L504)).
- **Block results:** a block's last expression already serves as its result in DESIGN's `fn f(s: Text) -> Text { s }` ([line 280](../DESIGN.md#L280)) and EXAMPLES' `make_table` ([line 427](../EXAMPLES.md#L427)); explicit `return` also appears. These can coexist; the grammar should formalize when the last expression supplies a value.

## Shared immutable data across threads

Frozen pools already fit ([DESIGN](../DESIGN.md#L442)): bounded per-file builders freeze without copying; a batch root lists their read-only partitions. Readers pin (keep alive) the root once and view field arrays; links are typed IDs, text is offset/length into payload blocks. The batch lives through its scope and reader pins; caches stay per job. Costs are bounded builder/payload memory, caches and reclamation bookkeeping. Read files in spawned jobs before pure parallel analysis; concurrent writes to one shared table remain off the table.

## Questions for Ben

1. Parameter modes: `write T`, `T write`, or another spelling? **Recommend `write T`**, matching the examples and exposing mode before type.
2. JSON routes: distinct `api`, or a `route` whose result selects HTML/JSON? **Recommend distinct `api`** for its response/error contract.
3. Rate limiting: exact global count through the writer, or approximate per-worker counts? **Recommend exact shared state for v1**; per-worker replication needs explicit routing and consistency rules.

## Smaller issues

- Change `percent` to `fn percent(part: long, whole: long) -> Ascii max 32` or constrain its inputs; max-long divided by one formats to 24 characters ([example](../EXAMPLES.md#L276)).
- `Job<Counts>` does not say how `count_file`'s `Result<Counts, ToolError>` is joined ([example](../EXAMPLES.md#L207)); specify whether join unwraps the job result, function result, or both.
- Freeze the test clock and define how scenarios advance it; capabilities can be fixed for tests, but no clock-advance operation is shown ([DESIGN line 615](../DESIGN.md#L615)).
