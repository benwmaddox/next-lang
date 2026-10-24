# Claude: T11 review (function values)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (all run and test fixtures), plus my own probes in ~/nlprobe:

- Function values passed, returned, stored in a struct field and a list, called through all of them; `pick(true)(6)` chaining; identity equality; printing gives the name.
- A printing function refused in a slot without `effects print`; allowed with it.
- Recursion through a function value (`b` passes itself to `a`) is caught as a call cycle.
- Global effect bounds: `writes app.score` / `reads app` paths.

Fix round 1 (prompt-T11-fix1.md):

1. Function types without a result (`fn(write int)`) didn't parse; now they mean `()`, and a mode mismatch names the parameter and both modes.
2. `writes P` didn't cover the reads that `P += x` needs; now it covers reads of `P` and paths under it, and `reads P` still refuses writes. DESIGN.md states the rule (one line in "Functions as values").

Carried forward: `effects print` becomes `effects out` in T20; the "recursion is not supported yet" wording changes in T19.
