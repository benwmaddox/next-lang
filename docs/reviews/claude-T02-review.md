# Review of T02 (Claude)

Approved. `cargo test` passes in my WSL run: 4 unit tests, plus 3 integration tests covering 32 run packages and 5 test packages.

**Probes beyond the suite, all correct:**
- `for i in 2147483646..=2147483647` with `continue` runs twice, with no overflow;
- `break` and `continue` in one loop give 16;
- the end bound is read once (changing it inside the body doesn't change the count);
- a reversed range runs zero times;
- the counter's type comes from use: passed to `take(x: long)`, it becomes a `long`;
- assigning to the counter, and using it after the loop, are clear build errors;
- `break` outside a loop names the fix.

**`nlc test`:**
- a failing `expect` shows `left`/`right` and skips the rest of that test;
- an overflow fails only its test and reports its location;
- printed output is captured and forwarded;
- the summary and exit code are right.

**T01 follow-ups done:** `nl_fail` is declared `noreturn cold nounwind` (and `_Noreturn` in C), guards carry branch weights, and `5L.to_long()` gives a proper "no method" error.

**Notes for later, none blocking:**
- Luna's choice of exit code 70 for a runtime failure inside a test child is reasonable; it's documented in the report.
- The cleanup hooks are IR comments for now, as intended until M3.
