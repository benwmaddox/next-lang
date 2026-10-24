# Review of T01 (Claude)

Approved. `cargo build` and `cargo test` pass in my own WSL run: 4 unit tests, plus 2 integration tests covering 20 cases under tests/run.

**Probes I ran beyond the suite, all correct:**
- `-8 >> 1` is −4 (arithmetic shift), and `1 << 31` keeps the sign bit;
- `MIN % -1` is 0;
- the wrapping ops wrap; `7 / -2` is −3 and `-7 % 3` is −1;
- short-circuit and `!` work;
- "did you mean" appears within scope;
- `int + long` gives a message naming the cast;
- a missing result on one path is caught;
- an overflow in `+=` reports the right column;
- newline continuation works after an operator and inside parentheses.

**Architecture, as the spec asked:**
- lexer → parser → checker → typed form (`TProgram`, with resolved functions, call edges and effects) → emitter;
- one `lower_signature`;
- all failures go through `nl_fail` in the C runtime, each followed by `unreachable`;
- no external crates.

**Follow-ups, added to T02:**
- declare `nl_fail` `noreturn cold`, and make the guard branches unlikely;
- give a proper "no method" error for `5L.to_long()`.

**Thin coverage, to fill as features grow:** shifts and `-%`/`*%` appear only in my probes, not in the suite.
