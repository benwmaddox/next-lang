# Review of T10 (Claude)

Approved. `cargo test` passes in my WSL run.

**Probes, all correct:**
- queue FIFO order and `Full` at capacity;
- `pop` and `peek`;
- a ring overwriting its oldest values (0 to 6 pushed into 3 slots gives `[4, 5, 6]`);
- a zero-capacity ring staying empty;
- a grid filled through a writable loop view in row order;
- `g[x, y]` indexing.

**Housekeeping:** a stray in-repo `target/` (233 MB of build output, from a build without `CARGO_TARGET_DIR`) is now in `.gitignore` and was deleted; prompts now repeat the target-directory rule.
