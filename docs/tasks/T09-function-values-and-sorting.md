# T09: function values and sorting (milestone M2, part 4)

Depends on T08. Same rules. Read DESIGN.md "Functions as values, no closures", including "A function type is a full contract" and "Patterns without closures".

## Function values

- A named top-level function is a value of a function type: `fn(int, int) -> bool`. It can be a local, a parameter, a field, an element of an array, list or map, and a global. No anonymous functions; nothing is captured.
- **A function type is a full contract:** parameter types and modes (`fn(write Counts, Entry)`), the result type, and the function's effects (in this task: whether it can `print`; a `fn(int) -> int` with no effects can't hold a function that prints, and the error names the difference). Assigning a function whose contract doesn't match the type exactly is a build error naming what differs.
- Calls through a value: `f(a, b)`. The call graph includes every function that can be stored in a value of that type (all functions whose address is taken with a matching type), so T01's recursion check still holds: a cycle through a function value is a build error.
- Owner and capacity parameters (T07) in function types: a value of `fn<P>(pool<Node<P>, 64, P>, Id<P>) -> long` is a build error in this task; function values are for plain types.
- Equality: two function values are equal when they name the same function. `print` shows the function's name.

## Sorting and searching (standard library, written in the language where possible)

- `sort_by(xs: write list<T, N>, ctx: C, less: fn(C, T, T) -> bool)` and the same for arrays; stable (equal elements keep their order). Also `sort(xs)` for lists of integers, `bool`s and payload-free enums in their natural order. Insertion sort for small inputs and merge sort with a fixed scratch buffer of the same capacity otherwise (no allocation: the scratch is a local of the same bounded type, under T06's 64 KB rule).
- `binary_search(xs, key) -> Option<long>` on a sorted list of integers.
- `ctx` is how a comparison gets extra data without closures (DESIGN.md "Patterns without closures").

## Acceptance cases

- A function value passed, stored in a struct field, in a list, in a map, and in a global; called through each.
- A contract mismatch (different parameter mode; an effect the type doesn't allow; a different result type), each a build error naming the difference.
- A recursion cycle through a function value (build error).
- `sort_by` with a context (sorting units by distance to a point given in `ctx`), stability on equal keys, already-sorted and reverse-sorted input, empty and one-element lists, a full list.
- `binary_search` found, not found, empty.

## Report

docs/tasks/T09-report.md.
