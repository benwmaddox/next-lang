# T06: fixed arrays and lists (milestone M2, part 1)

Depends on T05. Same rules (docs/PLAN.md, T01's Architecture section). DESIGN.md's first step, fixed-size part; pools and owner parameters are T07 (split after docs/reviews/sol-T06-r1.md). Read DESIGN.md "Collections", "Layout: structure of arrays", "Views of state that can change", "Bounds", "Sizes, indexes and time", and the step 1 acceptance cases.

## Scope

Fixed arrays and lists of **fixed-size elements** (scalars, enums, structs of those, and nested arrays and lists), as locals, parameters, struct fields and collection elements. No text in collections (M3), no globals (T08), no pools (T07).

## Declarations and construction

- `var a: int[8] = fill(0)` (the fill is evaluated once and copied), `let grid: Cell[16] = fill(Cell {})`, or `int[8]` alone when the element type has a valid default for every field (T04's rule otherwise: a required field with no default and no fill is a build error). `var xs: list<Item, 32> = list {}` starts empty without constructing unused elements.
- Capacities are constants. Zero is allowed; negative or non-constant capacities are build errors, and so is a total size whose element-count product overflows a `long`.

## Operations (indexes, counts and lengths are refined `long`s)

- **Arrays:** `a[i]` reads; `a[i] = v` writes (mutable storage only; the element's refinement applies); `a.len()` is a constant.
- **Lists:** `push(x) -> Result<(), Full>`; `pop() -> Option<T>`; `insert(i, x) -> Result<(), Full>` with `0 <= i <= count`; `remove(i) -> T` with `0 <= i < count` (shifts the rest down); `count()`; `xs[i]` with `0 <= i < count`; `clear()`.
- **Indexes:** an index the checker proves in range carries no check; otherwise it's checked at run time and fails through `nl_fail` with `index out of range`, before any store or capacity check. `for i in 0..a.len()` over an array is the common proven case.
- **`Full` and `discard`:** `Full` is a prelude error type. A push or insert's `Result` must be used; `discard xs.push(x)` drops it explicitly, and `discard` accepts only a collection operation's expected `Full`, not any `Result`. When the checker proves a push can't overflow (a counting analysis: N pushes into a fresh `list<T, N>`, or pushes bounded by a loop over a collection of at most the remaining capacity), the `Result` may go unused and its failure branch is removed. The expression's type stays `Result` either way, so `match`, `?` and `unwrap` still work on it. Facts used for this end after any write or call that could change the count.

## Loops and views

- `for x in coll` and `for x, i in coll` (`i` the index). Iteration covers the elements present when the loop starts, in index order; elements pushed during the loop aren't visited.
- Over a collection the function may write, `x` is a writable view of each element: writing `x.field` writes the collection. Over a read parameter or a `let` collection, views are read-only. `i` is immutable.
- While a view is live (inside the loop, ended at every exit through T02/T03's cleanup edges: `break`, `continue`, `return`, `?`), anything that would move or free elements is a build error: `pop`, `insert`, `remove`, `clear`, assigning the whole collection, or passing it as `write` to a helper. Pushing onto the end is allowed. Writing a fixed-size field of a different, provably distinct element is allowed.

## Places and overlap (extends T04)

- Places now include indexes: `a[i]`, `a[i].f`, `units[k].inventory[j]`. Receivers, indexes and arguments are evaluated once, left to right.
- Passing a whole collection and one of its elements, or two elements whose indexes aren't proven distinct, is a build error when either is `write`; provably distinct indexes or fields are fine, also through `write` parameters passed on.

## Layout and nesting

- A collection of structs is one array per field (structure of arrays); nested fixed-capacity collections flatten into more arrays (`inventory: list<Item, 8>` in each of 64 units becomes 64 × 8 items plus 64 counts). Show this in the emitted IR in one test (the field arrays, not an array of structs).
- Local collections live on the native stack in this task. That's a temporary deviation from DESIGN.md (which puts values over 4 KB on a data stack, M3): until then, a local collection over 64 KB, counting padding, nested storage and any hidden copies, is a build error saying it needs M3. Allocas for loop-body locals must not pile up per iteration.
- Small arrays and lists can be returned and passed by value through T01's signature lowering, and survive the scope that made them.

## Printing and equality

- `print` and `expect ==`: arrays and lists print as `[1, 2, 3]` (nested the same way). Equality compares lengths and active elements, never unused capacity or padding. T02's once-only operand capture still holds.

## Acceptance cases

- Construction: a fill evaluated once; a refined element type with and without a valid default; zero capacity; a negative or non-constant capacity (build errors); a size product overflow (build error).
- Lists: push to exactly capacity then `Full` with contents unchanged; `pop` on empty gives `none`; insert at 0 and at `count`; insert into a full list gives `Full` and changes nothing; remove shifts; remove and index past `count` fail at their line.
- Indexes: a proven index has no guard in the IR; an unproven one fails with `index out of range`; negative indexes; an `int` index needs a cast.
- `discard`: allowed on a push, refused on a non-collection `Result`; an unused push `Result` without proof is a build error; the proven N-into-N case needs no handling and `match` on it still works.
- Views: field writes through a loop variable reach storage; a push during iteration isn't visited; each forbidden operation under a live view (build error); the same operations after the loop work; nested loops.
- Overlap: whole collection plus element; two unproven indexes; proven-distinct indexes allowed; both argument orders.
- Nesting and layout: nested list counts are independent per element; the IR shows field arrays; a 70 KB local (build error).
- Constants: arrays and lists in a `const` evaluated at compile time (extend T05) agree with run-time results.

## Report

docs/tasks/T06-report.md.

## Decisions from Sol's second review (docs/reviews/sol-T06-T07-r2.md), binding

- **Nested views protect everything enclosing them:** while iterating `units[k].inventory`, replacing `units[k]`, assigning `units`, removing or shifting the element that contains it, and passing `units` or `units[k]` as `write` are build errors. Assigning a scalar loop binding (`for x in xs { x = 3 }`) writes the element when the collection is writable, and is a build error when it's read-only.
- **Counting facts for proven pushes:** a successful push adds one to the count the checker knows, a failed one leaves it unchanged; branch joins keep the larger possible count, and loop back edges take the most the loop can add. Other writes or calls that can change the collection end the fact. Tests: a bounded loop of pushes proven safe; a helper call in between that ends the proof (so the `Result` must then be handled); a proven push used with `?` and with `unwrap`.
- **`Full`:** the prelude has `Full` as a value and a type (one case, no payload): written `Full`, matched as `err(Full)`, and printed `Full`.
