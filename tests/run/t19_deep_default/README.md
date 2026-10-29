# Native stack exhaustion

`stage0.*` preserve the Rust Stage0 recursion-budget diagnostic. The target compiler uses native recursion without an implicit language budget. This deliberately excessive depth exhausts the operating-system native stack; the process terminates abnormally with status 128 and no output at O1 and O3.