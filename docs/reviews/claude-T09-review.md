# Review of T09 (Claude)

Approved. `cargo test` passes in my WSL run.

**Probes, all correct:**
- insertion order kept across updates;
- remove-then-add appending at the end;
- a full map refusing a new key (`err(Full)`);
- sets of enums de-duplicating;
- struct keys;
- equality independent of insertion order;
- writable map values through a loop view;
- adding a key under a live view refused.
