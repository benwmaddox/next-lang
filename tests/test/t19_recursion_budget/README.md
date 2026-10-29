# Recursion budget under native execution

`stage0.*` preserve the Rust Stage0 test oracle, which reports `recursion budget exhausted`. The target compiler uses native recursion: the oversized call terminates abnormally inside the test child, so the runner reports the test as terminated abnormally and exits 1. O1 and O3 produce the same target output.