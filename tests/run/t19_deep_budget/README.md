# Recursion below the native stack limit

`stage0.exit`, `stage0.stdout`, and `stage0.stderr` preserve the Rust Stage0 oracle, which stops at the configured recursion budget. The target compiler uses ordinary native recursion here; depth 10,000 completes and prints `10000` at O1 and O3.