# Recursive large result destinations

`stage0.*` preserve Rust Stage0's rejection of a large result destination live across recursion. The target compiler provides per-activation result storage; the recursive call returns the zero-filled base value, so output is `0` at O1 and O3.