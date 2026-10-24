You are the implementer (Luna) for next-lang. T04 (docs/tasks/T04-structs-refinements-const.md) is implemented and its tests pass, but Claude's review found one gap. Fix it, add tests, keep everything else passing, and append a short "Fix 1" section to docs/tasks/T04-report.md. Same rules as before: never commit or touch branches; don't edit docs other than the report; build and test in WSL with CARGO_TARGET_DIR=$HOME/.cache/next-lang/target.

The gap: the interval analysis doesn't narrow on equality. This must type-check with no cast, as DESIGN.md's Rocks example relies on it:

    type Size = int 1..=3
    fn smaller(r: Size) -> Size {
        if r == 1 { return 1 }
        r - 1        // r is 2 or 3 here, so r - 1 is 1 or 2: fits Size
    }

Today it reports "cannot prove this value fits Size". Fix: when a branch is taken on `x == c` or `x != c` with a constant c, narrow x's range on each side: on the `==` side to exactly c (if c is in range); on the `!=` side, remove c when c is an endpoint of x's range (an interior value can't be removed from an interval, so leave the range as it is). This applies to early exits (`if x == c { return ... }` narrows the rest of the block), to `else` branches, to `&&`/`||` combinations the analysis already handles for `<`/`>`, and to the loop forms T04 covers.

Tests to add (tests/run/): the `smaller` function above; `!=` narrowing in an `if` body; an interior value (`if r == 2 { return }` then `r - 1` must still need a cast, since r could be 1); equality on the upper endpoint; equality in a `while`-free loop with `continue`.
