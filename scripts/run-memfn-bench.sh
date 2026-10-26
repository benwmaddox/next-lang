#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock="/home/ben/linuxbench/bench.lock"
if [[ -e "$lock" ]]; then
    exec flock -x "$lock" python3 "$repo_root/scripts/run-memfn-bench.py" "$@"
fi
exec python3 "$repo_root/scripts/run-memfn-bench.py" "$@"
