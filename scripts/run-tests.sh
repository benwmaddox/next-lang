#!/usr/bin/env bash
# The whole selfhost suite, with no Rust: build the compiler from the checked-in seed, run the build comparison
# against the recorded reference results (tests/reference), then the Python tests in tests/py.
# Usage: scripts/run-tests.sh [compare options, e.g. --only 'tests/e3/*']
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -v 40000000 2>/dev/null || true
compiler="$(python3 scripts/build-selfhost-cached.py)"
export NLC_SELFHOST="$compiler"
status=0
scripts/run-frozen-suite.sh "$compiler" "$@" || status=$?
python3 -m unittest discover -s tests/py -p 'test_*.py' || status=$?
exit $status
