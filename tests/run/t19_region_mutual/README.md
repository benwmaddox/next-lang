# Mutual recursion with a live local arena

`stage0.*` preserve Rust Stage0's rejection of the large local kept live across the mutual-recursion cycle. The target compiler keeps one arena frame per activation, producing `3` at O1 and O3.