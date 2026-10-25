# Claude: T26 review (never-returning functions)

**Verdict:** approved, no fix round.

Checked: cargo build and test pass, including the self-host comparison (selfhost/ now uses `-> never` helpers for usage and failures). Probes: ~/nlprobe/v1 (`fn fail(env: Env, code: int 0..=125) -> never { env.exit(code) }` used in an `if` value branch and as a statement) prints 1 and exits 2; v3 (a `-> never` body that can fall through) is refused with "every path in a '-> never' function must end in a never expression". `never` is allowed only as a function or function-type result, and function results match exactly, as the task allowed.
