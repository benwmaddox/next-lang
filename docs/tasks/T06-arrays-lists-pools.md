# T06: fixed arrays, lists and pools (milestone M2, part 1)

Depends on T05. Same rules (docs/PLAN.md, T01's Architecture section). This is DESIGN.md's first step, fixed-size part: read DESIGN.md "Collections", "Layout: structure of arrays", "Pools and their ids" (including "Owner parameters in reusable definitions"), "Views of state that can change", "Bounds", and the step 1 acceptance cases under "First steps".

## Scope

Collections as **locals and parameters only** (globals are T07), holding **fixed-size elements only**: scalars, enums, structs of those, and ids. No text in collections yet (M3).

- **`T[N]`**: a fixed array, always N elements, `N` a constant. Created with a fill (`int[8] = fill(0)`) or element defaults. Indexing `a[i]` with `i: long` (indexes are `long`, DESIGN.md "Sizes, indexes and time"); an index the checker can't prove in range is checked at run time (a structured failure `index out of range`), and proven ones carry no check (use T04's interval analysis; `for i in 0..N` over an array is the common proven case). `a.len()` is a constant `long`.
- **`list<T, N>`**: up to N elements in order with a count. `push` returns `Result<(), Full>`, `pop` returns `Option<T>`, `insert(i, x)`, `remove(i)` (shifts), `count()`, indexing. A push the checker can prove can't overflow may skip the `Result` (DESIGN.md: "can't overflow" pushes); otherwise ignoring the `Result` is a build error and `discard` is the explicit way to drop it.
- **`pool<T, N>`** with **owner parameters** (DESIGN.md): `add(x) -> Result<Id<P>, Full>`, `get(id) -> Option<T>` (a copy), `remove(id)`, `count()`, `contains(id)`. Ids are 64 bits: a 32-bit slot and a 32-bit generation. A slot is a fixed position (holes, an occupied flag, a free list); removing bumps the generation; a stale id gives `none`; a slot whose generation reaches its maximum is retired. Each pool is a fresh owner; mixing two pools' ids is a build error naming both. Definitions that hold their own ids take an owner parameter (`struct Node<P> { parent: Option<Id<P>> }`), inferred at call sites.
- **Layout:** a collection of structs is stored as one array per field (structure of arrays): `pool<Rock, 64>` holds an array of each field plus the flags and generations. Nested fixed-capacity collections inside an element flatten into more arrays (`inventory: list<Item, 8>` in each of 64 units becomes 64 × 8 items plus 64 counts).
- **Loops and views:** `for x in coll` and `for x, i in coll` (`i` an index for arrays and lists, an id for pools). Over a collection the function may write, the loop variable is a writable view of each element. While a view of a collection is live, removing elements, `insert`/`remove` on a list, and anything else that would move or free elements is a build error; pushing onto the end of a list and adding to a pool are allowed (DESIGN.md "Views of state that can change").
- **Bounds:** capacities are part of the type and must be constants; a collection without one is a build error. Local collections live on the native stack in this task (no data stacks yet, M3); a local collection bigger than 64 KB is a build error for now, saying it needs M3's data stacks.
- `print` and `expect ==` work on collections (elements in order; pools in slot order with ids).

## Acceptance cases (DESIGN.md step 1, the parts this task owns)

- A live lookup succeeds; out-of-range and stale ids return `none`; removing an element and reusing its slot doesn't change which element any other id names, and no element moves between slots; a slot set up near the maximum generation is retired, not reused; an id from another pool is a build error.
- Adding at exactly the capacity succeeds and the next returns `Full` without changing the collection; a list `insert` into a full list returns `Full` and changes nothing.
- A view of a pool live while the loop removes from it is a build error; collecting ids and removing after the loop works.
- A nested `list<Item, 8>` inside a pool element flattens, and its count is per element.
- A self-linked `Node<P>` tree built in a pool; a helper taking `pool<Node<P>, N, P>` and returning `Id<P>`; two pools of the same plain struct; a helper returning an id of a pool that dies on return (build error).
- Proven indexes carry no check (look for the absence of the guard in the emitted IR in one test) and unproven ones fail with `index out of range` at their line.

## Report

docs/tasks/T06-report.md.
