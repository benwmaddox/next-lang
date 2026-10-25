# Claude: T27 review (stack attribution and the 192 GB worst case)

**Verdict:** approved, no fix round.

Checked: cargo build and test pass (17 groups, including the selfhost comparison); `nlc inspect stacks selfhost` now reports 904,669,490 bytes (was 192,745,324,820), attributes it along the critical path `main -> output_tree_dump -> ... -> append_unicode_byte_value` with contributions that sum exactly to the total, and lists no copy-down sites.

Cause: an analyzer overcount. Large place arguments (`write ParseTables` and the like, passed by pointer) were counted as staged copies at every call, accumulating along the parser's call chains. Also fixed: static byte-string arguments sized at the parameter's maximum rather than the literal's size; a `Bytes`-returning call into a destination now builds there directly; `buffer = Bytes.empty()` resets the descriptor instead of a 1 MiB copy-down (which removes the five sites T30 item 1 named; T30 still covers the general `buffer = f(buffer)` case); a large iteration element inside a `match` arm was missing from the region requirement.

What remains is real: 870 MB of declared fixed-capacity regions in the self-hosted `main` (616.9 MB of parse tables, source, tokens, directory entries, the per-file buffer). Under the offset plan that becomes address range the stack can grow into, not an up-front reservation.
