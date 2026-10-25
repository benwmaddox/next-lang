# Claude: T29 review (inline text fields in structs and payloads)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (selfhost comparison included). Struct fields, enum, `Option` and `Result` payloads now store text and bytes as length (and code points) plus inline bytes, with no pointer; copies move live bytes only; `emit_rebase_growing_payload` and the pointer-bearing option types are gone. `tests/run/t24_static_string_sum` now succeeds (a constant `Option<Ascii>` was a build error before), which T29 requires.

Fix round 1: the self-hosted parser had become 15-18% slower. Luna profiled before and after with perf: T29 copied each read-only string literal (`" name="` and so on) into an inline temporary allocated through `nl_stack_alloc`, 48 calls in `dump_node_fields` alone. Literals are now static data referenced by a transient descriptor. Result: the parser at 0.25 s best of 5 (my run of scripts/bench-selfhost.sh) against 0.37 s before T29; RSS unchanged.

Findings for later:

- `nl_stack_alloc` is an out-of-line runtime call and took 35% of the parser's samples even before T29. Region allocation should be an inline bump of the cached top with an out-of-line slow path only for growth; added to the offset milestone (O1), where the base and top are cached anyway.
- Collections still store `{ptr, len}` descriptors in their text lanes and reuse slots by pointer range: T31.
