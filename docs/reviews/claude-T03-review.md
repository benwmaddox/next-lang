# Review of T03 (Claude)

Approved. `cargo test` passes in my WSL run: 3 integration tests covering 55 run packages and 6 test packages.

**Probes, all correct:**
- `match` on payload enums;
- `?` on `Option` and `Result` (an error passed up from the first failing call);
- `?.` flattening (`half(10)?.half()` is `none`) and skipping on `none`;
- `??` with a default and with `continue` in a loop;
- structural equality;
- printing a nested `some(none)`;
- a non-exhaustive match naming the missing case;
- `??` on a `Result` refused with the fix;
- `unwrap()` on `none` failing at its location.

**Follow-up, added to T04:** `x.to_long()` works but `x?.to_long()` says "unknown function 'to_long'". `?.` resolves only named functions, which is what the task said, but it should also accept the built-in methods that `.` accepts, so the two forms agree.
