# Recursive live arena frame

The Stage0 O1 and O3 compiler runs reject this case because `frame` remains live across a recursive call. Their captured output is preserved in `stage0.stdout`, `stage0.stderr`, and `stage0.exit`.

The target oracle exercises the B1 behavior: each activation keeps its own `list<long, 60000>` frame alive while the child recurses, then reads that frame after the child returns. At depth 2, the values combine as `2 * 100 + (1 * 100 + 0)`, so the expected output is `300`.