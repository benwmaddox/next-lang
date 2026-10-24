# Claude: T13 review (data stack, regions, destination emission)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (the suite now includes stack_contracts.rs IR checks, t13_stack_contracts, t13_soa_gather and the shrunken-reservation exhaustion test). Probes in ~/nlprobe:

- d1: a function building and returning a 1.6 MB list, called 2,000 times in a loop with `continue`, a copy and `break`: correct sum (499,500,000,000), 0.4 s, 98 MB peak, so iteration cleanup restores the top on every exit.
- Large structs (8 KB) through `if`, `match` on `some(x)`, `fill` of an array of them, element assignment from a call result, element-to-element copy, equality.
- e7: a `write` list element passed three times to a callee that fails on the third through `?`: `err(3)`, and the element's count is 3 afterwards (copy-back on the failure path), then a `write` loop view changes it.

Fix round 1 (prompt-T13-fix1.md): passing any element of a collection of large structs to a function panicked the compiler (structure-of-arrays elements have no single address). Now such an argument is gathered into a temporary region, passed by address and, for `write`, scattered back after the call on every exit. This is a copy per call; a zero-copy scheme (passing the element's lanes and index) is a later optimisation, worth doing when the layout follow-up before M4 flattens nested lanes.

Notes:

- Byte requirements are conservative (main in t13_soa_gather: 603 KB); T17's reservations will show whether that over-reserves badly.
- `map` has `get`/`set`, not `insert`; my probe used the wrong name.
