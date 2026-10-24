# Review of T04 (Claude)

Approved after one fix round. `cargo test` passes in my WSL run: 91 run packages and 7 test packages.

**Probes, all correct:**
- `clamp` health (100 → 70 → 0);
- `wrap` heading (370 → 10, then −20 → 350);
- `fit` giving `none`;
- a checked cast failing at run time;
- struct copies being independent;
- separate fields allowed in one call while the same field passed twice is an overlap error;
- `write` on a `let` refused;
- a stale fact after reassignment correctly refusing a store;
- the unproven-store error naming both explicit forms.

**Fix 1:** equality narrowing was missing, so `if r == 1 { return 1 }` followed by `r - 1` wasn't proven to fit `Size` (DESIGN.md's Rocks example needs it). After the fix:
- `==` and `!=` narrow at the ends of a range;
- an interior exclusion (`r == 2`) still needs a cast, as it should, since a range can't have a hole.
