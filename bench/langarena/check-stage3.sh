#!/bin/bash
# Build each bench/langarena package with a self-hosted compiler (--runtime=c, clang) and compare its
# test-mode checksum with LangArena's. Usage: check-stage3.sh <stage3 compiler> [package ...]  (run in WSL/Linux)
cd "$(dirname "$0")/../.."
S3=$1; shift
mkdir -p target/langarena-stage3
pkgs=${@:-$(ls bench/langarena | while read p; do [ -f bench/langarena/$p/name ] && echo $p; done)}
pass=0; fail=0
for p in $pkgs; do
  d=bench/langarena/$p
  name=$(cat $d/name)
  want=$(python3 - "$name" <<'PY'
import json,sys
for t in json.load(open("bench/langarena/test.js")):
    if t["name"]==sys.argv[1]: print(t["checksum"])
PY
)
  rm -f target/langarena-stage3/$p.ll target/langarena-stage3/$p
  msg=$($S3 build $d -o target/langarena-stage3/$p.ll --runtime=c 2>&1 | head -1)
  if [ ! -f target/langarena-stage3/$p.ll ]; then echo "BUILD  $p: $msg"; fail=$((fail+1)); continue; fi
  clang -O1 -DNLC_STACK_MODE_OFFSET=1 -o target/langarena-stage3/$p target/langarena-stage3/$p.ll runtime/nl_runtime.c -lm 2>/dev/null || { echo "CLANG  $p"; fail=$((fail+1)); continue; }
  got=$(timeout 20 target/langarena-stage3/$p test 2>&1 | tail -1)
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else echo "WRONG  $p: want $want got ${got:0:80}"; fail=$((fail+1)); fi
done
echo "pass=$pass fail=$fail"
