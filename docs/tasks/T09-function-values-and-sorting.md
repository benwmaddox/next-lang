# T11: function values (milestone M2, part 6)

This file kept its old name for history; the task is **T11**. Depends on T10. Same rules. Read DESIGN.md "Functions as values, no closures". Reviewed: docs/reviews/sol-T08-T09-r1.md (points 9 and 12). Sorting is T12 (docs/tasks/T12-sorting.md).

## Function values

- A named top-level function is a value of a function type: `fn(int, int) -> bool`. It can be a local, a parameter, a result, a field, an element of an array, list or map, and part of a global. No anonymous functions (an attempt is a build error saying so); nothing is captured. A function-typed field has no implicit "null": a struct literal must give it, like any required field.
- **The contract:** parameter types and modes and the result type must match exactly. Effects are an upper bound written on the type: `fn(int) -> int` has no effects; `fn(int) -> int effects print` may print. A function with fewer effects than the bound fits (a pure function in a `print`-allowed slot); one with more doesn't, and the error names the extra effect. Reading or writing globals (T08) counts as an effect for this purpose: `effects reads app` / `writes app` (field paths allowed), so a comparator can't secretly change what it's sorting.
- **Calls through a value:** `f(a, b)`. The call graph gets an edge to every address-taken function that fits the value's type (not only exact matches), so T01's recursion check, T05's cacheability and T08's hidden-access checks all see through function values: widening can't hide recursion, printing or global access.
- Suspension, append mode and data-stack contracts in function types are M3 and later. Owner- or capacity-generic function values (`fn<P>(...)`) are a build error in this task; a concrete owner-typed signature (`fn(Id<app.nodes>) -> long`) is allowed.
- Equality: two function values are equal when they name the same function; `print` shows the name.

## Acceptance cases

A function value passed, returned, stored in a struct field, an array, a list, a map and a global, and called through each; a pure function in a `print`-allowed slot (allowed); a printing function in a pure slot (build error naming `print`); a parameter-mode or result mismatch (build error); recursion through a function value (build error); a function value reaching `print` used by a `const` (build error); a comparator that writes the global it's given (build error); an anonymous function (build error); a missing function field (build error); identity equality and printing.

## Report

docs/tasks/T11-report.md.
