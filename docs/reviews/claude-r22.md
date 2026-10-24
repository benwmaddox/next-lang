# Reply to review 22 and claude-ex-r2 (examples, pass 2)

**Ben's decisions (2026-10-24):**
- **Ranges are Rust-style everywhere:** `..` excludes the end and `..=` includes it. Every inclusive refinement in DESIGN.md and EXAMPLES.md is now `..=`; the wrapping float angle stays `..`.
- **Loop counters** take their type from their bounds and use.

Both are recorded in DESIGN.md, and both open points are closed.

**Codex points, all applied:**
- **logsum's parser:** one step per line, so no `?.` lands on an `Option`-returning method. The flattening question is now an open point.
- **`HttpStatus`:** a named refinement.
- **`refill`:** keeps the fraction after a long wait, and the cap is written as `min` where it's computed. Your 60.5 s / 61 s case is a test.
- **Cross-file test:** reads two real in-memory files through `count_file`, with B holding 20,000 distinct paths, and expects `untracked == 1`.

**Clarity, from both reviews:**
- **Rocks:** `safe` → `invulnerable_ticks`; `hit`/`spent` → `hit_rock_ids`/`spent_bullet_ids`; no `f` suffixes, since floats take their type from context.
- **logsum:**
  - `io` → `tool_result`; `c`/`e`/`p`/`i` → `counts`/`entry`/`top`/`rank`;
  - the shadowed `line` is now `read` → `line`;
  - `skipped` is split into `unparsed` and `untracked`.
- **API:** `since` → `refilled_through`; `.ok() ?? false` → `match`; a comment links the chat model; a comment says a new address starts full.
- **CRC:** `t`/`c` → `table`/`remainder`.

**Ratings this pass:**

| | Rocks | logsum | API | CRC |
| --- | --- | --- | --- | --- |
| Codex | 3 | 3 | 3 | 4 |
| Claude | 3 | 2 | 4 | 5 |

The changes above target what both called out.
