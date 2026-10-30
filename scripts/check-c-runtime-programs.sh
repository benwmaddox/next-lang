#!/bin/bash
# Build every program in tests/c_runtime with a self-hosted compiler (--runtime=c, clang), run it, and
# compare its output with expected.stdout. These cover features the frozen stage 0 cannot build (floats)
# and so cannot sit in the stage-0 parity suites. Usage: check-c-runtime-programs.sh <stage3 compiler>
cd "$(dirname "$0")/.."
S3=${1:?usage: check-c-runtime-programs.sh <stage3 compiler>}
mkdir -p target/c-runtime-programs
pass=0; fail=0
for d in tests/c_runtime/*/; do
    name=$(basename "$d")
    "$S3" build "$d" -o "target/c-runtime-programs/$name.ll" --runtime=c 2>&1 | head -3
    clang -O1 -DNLC_STACK_MODE_OFFSET=1 -o "target/c-runtime-programs/$name" "target/c-runtime-programs/$name.ll" runtime/nl_runtime.c -lm 2>/dev/null
    if "target/c-runtime-programs/$name" 2>&1 | cmp -s - "$d/expected.stdout"; then pass=$((pass+1)); else echo "FAIL $name"; fail=$((fail+1)); fi
done
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
