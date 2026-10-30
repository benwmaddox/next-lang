#!/usr/bin/env bash
# Run the selfhost build comparison with no Rust compiler: the reference results come from tests/reference
# (recorded with NLC_RECORD_REFERENCE=1 scripts/compare-selfhost.sh --build --reference <nlc>), and programs
# are linked by scripts/nlc. Usage: scripts/run-frozen-suite.sh <self-hosted compiler> [compare options...]
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
compiler="${1:?usage: scripts/run-frozen-suite.sh <self-hosted compiler> [options]}"
shift
cd "$repo_root"
# The compiler needs a large address space (the data stack reserves 16 GiB).
ulimit -v 40000000 2>/dev/null || true
NLC_REFERENCE=frozen exec python3 scripts/compare-selfhost-build.py --reference /nonexistent/nlc \
    --compiler "$(cd "$(dirname "$compiler")" && pwd)/$(basename "$compiler")" "$@"
