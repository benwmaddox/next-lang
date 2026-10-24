# Review of T07 (Claude)

Approved after one fix round. `cargo test` passes in my WSL run: 162 run packages, plus IR tests for collections and pools.

**Probes, all correct:**
- a self-linked `Node<P>` tree with an inferred `depth<P, N>` helper;
- `remove` returning the element;
- a stale id giving `none` even after its slot is reused;
- two pools of one plain type side by side;
- another pool's id refused ("expected b.Id, got a.Id");
- an id escaping a dying pool refused;
- pools made in a loop each a fresh owner.

**Fix 1:** `Option<Id<P>>` didn't parse (the closing `>>` lexed as a shift), and that's DESIGN.md's own syntax. It's fixed in type contexts, with shifts unaffected.
