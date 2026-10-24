# T07: pools and owner parameters (milestone M2, part 2)

Depends on T06. Same rules. Read DESIGN.md "Pools and their ids" including "Owner parameters in reusable definitions", and docs/reviews/sol-ids-r1.md and sol-T06-r1.md.

## Pools

- `var rocks: pool<Rock, 64> = pool {}`. `add(x) -> Result<Id<rocks>, Full>`; `get(id) -> Option<T>` (a copy: changing it doesn't change the pool); `remove(id) -> Option<T>` (a stale, unoccupied or out-of-range id gives `none` and changes nothing); `contains(id)`; `count()` (a refined `long`). Writable access to an element is through a loop view (`for r, id in rocks`); `rocks[id].field` is deferred.
- Ids are 64 bits: a 32-bit slot and a 32-bit generation. A slot is a fixed position with an occupied flag; a free list reuses slots; removing bumps the generation; a slot whose generation reaches its maximum is retired, never reused. A pool's capacity above 2^32 slots is a build error.
- Loops: `for r, id in rocks` visits occupied slots present at the start, in slot order; `id` is immutable. T06's view rules apply: no `remove` under a live view; `add` is allowed.
- Layout: one array per field plus the occupied flags and generations, as in T06.

## Owner parameters (DESIGN.md)

- Each pool is a fresh owner, including pools made repeatedly at one line in a loop. `rocks.Id` is shorthand for `Id<rocks>`. Mixing ids of two pools is a build error naming both (`expected rocks.Id, got other.Id`).
- A definition holding its own ids takes an owner parameter: `struct Node<P> { parent: Option<Id<P>> }`, and the pool binds it to itself: `var nodes: pool<Node<nodes>, 4096> = pool {}`. The pool's own name is in scope in its type for exactly that.
- Helpers take owner and capacity parameters, inferred at call sites: `fn depth<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> long`. This task adds generics only for owner and capacity parameters; general type generics and traits are later. Put a limit on how many instantiations a program makes (say 10,000) and make passing it a build error.
- A helper may return ids of a pool its caller owns; returning an id of a pool that ends when the helper returns, directly or hidden in a struct or `Option`, is a build error.
- **Copies, returns and resets of pools are refused in this task** (DESIGN.md describes the rules, with fresh owners for copies; they come later): assigning a whole pool, returning one, and passing one by value are build errors that say so. Read parameters borrow the caller's pool and owner. Pools inside repeated elements (a pool in each element of a list) are a build error, as DESIGN.md says (an outer index can't give each one its own owner).

## Printing and equality

- `print`: `pool{0:1 => Rock(...), 3:2 => Rock(...)}` (slot:generation => value, in slot order). Equality of two pools of the same owner compares occupied slots, their generations and values, ignoring free-list order and vacant history; pools of different owners can't be compared (build error).

## Acceptance cases (DESIGN.md step 1, pool part)

- A live lookup succeeds; a stale id gives `none`; removing an element and reusing its slot doesn't change which element any other id names; no element moves between slots; double removal gives `none` the second time.
- Using an internal test hook (not language syntax) to make an out-of-range id and a slot near its maximum generation: the out-of-range id gives `none`, and the slot is retired, not reused.
- Adding at exactly capacity then `Full` with the pool unchanged.
- Owners: an id of another pool (build error naming both); two pools of the same plain struct working side by side; pools made in a loop each a fresh owner; a self-linked `Node<P>` tree; a helper taking `pool<Node<P>, N, P>` and returning `Id<P>`; a helper returning an id of a dying pool, directly and inside an `Option` (build errors); copying, returning and assigning a pool (build errors); a pool inside list elements (build error).
- Views: removing under a live view (build error); collecting ids and removing after the loop works; `get` returns a copy.
- Constants: pools in a `const`, evaluated at compile time, agreeing with run time.

## Report

docs/tasks/T07-report.md.

## Decisions from Sol's second review (docs/reviews/sol-T06-T07-r2.md), binding

- **Pools inside structs:** a local struct may have a pool field; its owner is named by its path (`state.nodes.Id`, `Id<state.nodes>`). Copying, returning, replacing or assigning any value that contains a pool, at any depth and including through a `write` parameter (`s = State {}` where `s: write State` holds a pool), is a build error, so a reset can't be slipped in by replacing the struct around a pool. Pools in elements of arrays or lists, directly or through structs, are a build error. Copying with rebinding (DESIGN.md) is scheduled after M3.
- **Constants:** a constant's evaluation may use a local pool inside a function that returns a plain value; a pool-valued constant (`const P: pool<...>`) is a build error for now.
- **Owner parameters, completed:**

  ```
  struct Node<P> { parent: Option<Id<P>>, value: int }
  fn depth<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> long {
      var d = 0L
      var cur = id
      for step in 0..N {                         // at most N links
          let node = nodes.get(cur) ?? return d
          let up = node.parent ?? return d
          cur = up
          d += 1
      }
      d
  }
  fn main() {
      var nodes: pool<Node<nodes>, 256> = pool {}
      let root: nodes.Id = nodes.add(Node { parent: none, value: 1 }).unwrap()
      let leaf: Id<nodes> = nodes.add(Node { parent: some(root), value: 2 }).unwrap()
      print(depth(nodes, leaf))                  // P and N inferred: prints 1
  }
  ```

  - The `P` argument in `pool<Node<P>, N, P>` refers to the pool's existing owner; it can't attach that owner to other storage.
  - Scope checks cover storing an id anywhere that outlives its pool, recursively through structs, enums, `Option`s and collections, not only returns.
  - Owner parameters exist only at compile time and are erased in generated code (one compiled function serves every owner); capacity parameters make a copy per distinct capacity. The limit of 10,000 counts capacity copies only.
  - Tests: carrying an id from one loop iteration's pool into the next iteration's (a fresh owner each time: build error); the same through repeated calls to a function that makes a pool; storing an id in a longer-lived struct (build error).
- **T06's contracts apply to pools:** `add`'s `Result` is mandatory to handle, `discard` drops `Full` explicitly, a proven add may skip handling with its type unchanged, and mutations need mutable storage. Capacity zero is allowed; capacities must be constants. The temporary 64 KB limit counts the flags, generations, free list and temporaries, so the example above uses 256 nodes. Nested views extend to pools: while iterating an element's nested list, removing that element is a build error.
- **Nesting acceptance case:** a pool whose elements hold a `list<Item, 8>`: the counts are independent per element, and the emitted IR shows flattened field arrays.
