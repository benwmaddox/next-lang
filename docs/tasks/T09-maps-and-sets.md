# T09: maps and sets (milestone M2, part 4)

Depends on T08. Same rules. Reviewed: docs/reviews/sol-T08-T09-r1.md (points 5 to 8 and 13, folded in).

## Types and keys

- `map<K, V, N>` and `set<K, N>`, bounded, fixed-size elements only (as T06). Constructors `map {}`, `set {}` start empty.
- Keys: integers, `bool`, payload-free enums, owner-typed ids (`units.Id`; hashed and compared by slot and generation, with the owner checked statically), and structs or enums built only from those. Any other key type is a build error (traits come later). Hashing and equality use the logical fields, never padding.
- Values (and keys) can't be or contain pools, at any depth (T07's rule); a map value or set element that holds a local pool's id where the map outlives the pool is a build error (T07's scope check).

## Operations

- Map: `get(k) -> Option<V>` (a copy); `set(k, v) -> Result<(), Full>` (an update of an existing key always succeeds and keeps its position; a new key in a full map is `Full` with the map unchanged); `remove(k) -> Option<V>`; `contains(k)`; `count()` (a refined `long`). Set: `add(k) -> Result<(), Full>` (adding an existing key succeeds); `remove(k) -> bool`; `contains(k)`; `count()`.
- T06's contracts carry over: results must be handled or `discard`ed (only `Full`), proven successes may skip handling with the type unchanged, mutations need mutable storage.

## Storage and order

- Entries live in a stable array in insertion order, with a separate fixed hash index (open addressing, a bounded number of probes) and removal marks; a removed key's slot is reused only by compaction, which happens only when no view is live and only inside `set`/`add` of a new key. Every lookup and insert ends within a fixed number of probes (the table's capacity), so a table full of removal marks can't loop forever.
- Iteration order is the order keys were first inserted: updating keeps a key's position, removing deletes it, adding it again appends it. `for v, k in m` (keys immutable, values writable views under T06's rules) and `for k in s`.
- Under a live view of a map or set (or of anything inside one), adding a new key, removing, and replacing the viewed value or anything enclosing it are build errors; writing a field of the viewed value is allowed.

## Printing and equality

- `print`: `{1: 10, 2: 20}` and `{1, 2}` in iteration order. Equality: same keys and equal values, whatever the insertion order.

## Acceptance cases

Hash collisions (keys chosen to collide); repeated updates keeping order; remove then re-add appending; a table filled with removal marks still finishing lookups; a full map refusing a new key but accepting an update, contents unchanged; struct and id keys; an unhashable key type (build error); a key write under iteration (build error); a value-field write under iteration (allowed); a nested-container invalidation through a helper (build error); equality independent of insertion order; compile-time and run-time agreement for a map built in a `const`.

## Report

docs/tasks/T09-report.md.
