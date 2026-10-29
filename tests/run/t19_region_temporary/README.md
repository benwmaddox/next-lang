# Recursive large argument temporary

`stage0.*` preserve Rust Stage0's rejection of a large temporary argument copied across recursion. The target compiler gives each activation its own arena storage, and the base value prints `1` at O1 and O3.