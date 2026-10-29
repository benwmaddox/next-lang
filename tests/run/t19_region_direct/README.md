# Recursive function-local arena

`stage0.*` preserve Rust Stage0's rejection of a large local kept live across direct recursion. The target compiler allocates a separate live arena frame per activation; the two recursive calls and the base frame produce `3` at O1 and O3.