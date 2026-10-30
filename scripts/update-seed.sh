#!/usr/bin/env bash
# Refresh seed/seed.ll.gz from the current sources: build the compiler from the existing seed, check that
# it reproduces itself (stage 2 == stage 3 IR) and store that IR as the new seed. Run it when selfhost/ starts
# using something the old seed cannot compile. Usage: scripts/update-seed.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -v 40000000 2>/dev/null || true
compiler="$(python3 scripts/build-selfhost-cached.py)"
rm -f .seed-stage2.ll .seed-stage3.ll
"$compiler" build selfhost -o .seed-stage2.ll --runtime=c
clang -O1 -DNLC_STACK_MODE_OFFSET=1 .seed-stage2.ll runtime/nl_runtime.c -o .seed-stage2
./.seed-stage2 build selfhost -o .seed-stage3.ll --runtime=c
cmp .seed-stage2.ll .seed-stage3.ll
gzip -9 -c .seed-stage3.ll > seed/seed.ll.gz
rm -f .seed-stage2 .seed-stage2.ll .seed-stage3.ll
echo "seed updated: $(wc -c < seed/seed.ll.gz) bytes"
