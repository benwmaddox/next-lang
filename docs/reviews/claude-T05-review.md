# Review of T05 (Claude)

Approved. `cargo test` passes in my WSL run (101 run packages).

**Probes, all correct:**
- a forward reference (`LIMIT = SQUARE + 1`);
- `fib(50)` computed at compile time (12,586,269,025), equal to the run-time result;
- an effect reached indirectly refused with the full chain (`constant X -> wrap -> noisy -> print`);
- a constant cycle named (`A -> B -> A`);
- the 10-million-step limit stopping a runaway loop.

**Note:** array-valued constants (the CRC table in EXAMPLES.md) need T06's arrays; T06 already says to extend the evaluator to arrays and lists.
