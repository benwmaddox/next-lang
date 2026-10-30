#!/usr/bin/env bash
# Pre-commit check (Ben, 2026-10-27): run the selfhost suite on exactly what is staged
# (scripts/run-tests.sh: the compiler is built from the checked-in seed, the build comparison reads the recorded
# reference results, then the Python tests run). Commits that change only docs (*.md, docs/), bench/ or these
# hook scripts skip it. Install with scripts/install-hooks.sh. Works from Git for Windows (re-runs itself in WSL)
# or directly inside WSL.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    repo="$(git rev-parse --show-toplevel)"            # e.g. D:/code/next-lang
    drive="$(tr '[:upper:]' '[:lower:]' <<<"${repo:0:1}")"
    exec env MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc "cd /mnt/$drive/${repo:3} && scripts/precommit-full.sh"
fi

changed="$(git diff --cached --name-only)"
if [[ -z "$changed" ]] || ! grep -qvE '^docs/|^bench/|\.md$|^scripts/(precommit-full|install-hooks)\.sh$' <<<"$changed"; then
    echo "pre-commit: only docs, benchmarks or hook scripts changed, skipping the full suite"
    exit 0
fi

# Concurrent commits (main checkout and worktrees) share one cache directory; take turns.
mkdir -p "$HOME/.cache/next-lang"
exec 9>"$HOME/.cache/next-lang/precommit.lock"
if ! flock -n 9; then
    echo "pre-commit: waiting for another commit's suite to finish ..."
    flock 9
fi

snapshot="$(mktemp -d /tmp/next-lang-precommit.XXXXXX)"
trap 'rm -rf -- "$snapshot"' EXIT
git checkout-index -a -f --prefix="$snapshot/"
echo "pre-commit: running the selfhost suite on the staged tree in $snapshot (limit 1 hour) ..."

cd "$snapshot"
export CARGO_TARGET_DIR="$HOME/.cache/next-lang/cache-precommit"   # where the compiler cache lives
start=$(date +%s)
status=0
timeout --foreground 3600 scripts/run-tests.sh || status=$?
elapsed=$(( $(date +%s) - start ))
if (( status == 124 )); then
    echo "pre-commit: FAILED: the suite passed the one-hour limit (${elapsed} s)"
elif (( status != 0 )); then
    echo "pre-commit: FAILED: the suite failed (status $status, ${elapsed} s)"
else
    echo "pre-commit: selected suites passed in ${elapsed} s"
fi
exit "$status"
