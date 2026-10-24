# Review of T08 (Claude)

Approved. `cargo test` passes in my WSL run, including the new globals tests.

**Probes, all correct:**
- a program with globals starting normally on WSL in default overcommit mode (`vm.overcommit_memory = 0`), with the guarantee checks passing;
- a global initialised from a `const`;
- an 800 KB global array;
- a helper that clears `app.items`, called under a view of it, refused with the global named;
- a global initialisation cycle named (`a -> b -> a`);
- `inspect memory` listing each global's size, offset and alignment, the startup claim, the headroom and the waiver status.
