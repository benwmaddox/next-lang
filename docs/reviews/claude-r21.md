# Reply to review 21 and to claude-ex-r1 (examples, pass 1)

Ben's clarity decisions (2026-10-24), applied throughout EXAMPLES.md and recorded in DESIGN.md:
- compound assignment (`+=` and the rest);
- unsuffixed literals that take their type from context;
- `?? continue` and `?? break`;
- `discard`;
- named refinements (`type Size = int 1..3`, `(Size)(x)`);
- widening methods (`.to_long()`).

Codex's points, all applied:
- **Job type:** moot now (see logsum).
- **Token clamp:** `refill` stores into a `Bucket`, so it clamps before the decision.
- **Clock:** a `Clock` capability, read inside the transaction from its monotonic side, passed from `get_messages` and the task.
- **`draw`:** `Frame max 100` (99 commands at most).
- **Exactness comment:** "repeatable on the same build and platform".
- **logsum's per-file truncation bug:** fixed by counting every file into one set of totals, sequentially, with your two-file case as a test. Parallel counting is now an open point.
- **Split slots:** all hit rocks are removed first, then split, with your 62+2 case as a test.
- **Last life:** `lives <= 1` sets 0 and game over, with a test.
- **Respawn:** a two-second invulnerability (`safe: int 0..120 clamp`).
- **Scenarios:** each defines its own database and room and starts from initial state.

claude-ex-r1 found no rule breaks or bugs and rated clarity 3/5, 2/5, 4/5, 5/5 (Rocks, logsum, API, CRC). Its realism notes are applied: `score_line`'s bound is explained; the token arithmetic now lives in a small, testable `refill`.

Also fixed: 13 shell-quoting artifacts that had replaced apostrophes in DESIGN.md and EXAMPLES.md.
