# Claude: H1b review (one input policy; speed items dropped)

**Verdict:** approved, no fix round. Only item 1 was in scope (the compilers were split; PLAN.md Order of work item 3).

Checked: Luna ran both full suites (NLC_FRONTEND=rust and selfhost); my run of the default suite passes (23 groups) in 720 s. Every command (`run`, `build`, `test`, `parse`, `lex`) under both front ends applies the same limits in the same order with the same messages (256 files, 16 MiB per file, 64 MiB per package, 1,000,000 tokens per file, 4,000,000 per package, 2,048 delimiter nesting, 1,000 parser nesting, 2,000,000 nodes and edges, the work limit); invalid UTF-8 is a syntax diagnostic with status 2 everywhere. compiler/tests/input_policy.rs checks each limit at N and N+1 across all five commands and both front ends. docs/syntax-tree-format.md describes the one policy.

Follow-up (PLAN small fixes): the suite went from about 6-7 minutes to 12, mostly the new input-policy matrix building maximum-size packages for every command and front end. Generate the large packages once and share them, and run the full cross-product only in a long mode, keeping N and N+1 per limit in the default run.

Housekeeping: removed empty `.agents`, `.aws` and `.codex` folders that Codex's sandbox left in the repo root (empty, so never tracked).
