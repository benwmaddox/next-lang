#!/usr/bin/env bash
# Pre-commit check (Ben, 2026-10-27): run the selfhost suite on exactly what is
# staged, and include the Rust suite when compiler implementation files changed.
# Commits that change only docs (*.md, docs/), bench/ or these hook scripts skip it. Install with
# scripts/install-hooks.sh. Works from Git for Windows (re-runs itself in WSL)
# or directly inside WSL.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    repo="$(git rev-parse --show-toplevel)"            # e.g. D:/code/next-lang
    drive="$(tr '[:upper:]' '[:lower:]' <<<"${repo:0:1}")"
    exec env MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc "cd /mnt/$drive/${repo:3} && scripts/precommit-full.sh"
fi

changed="$(git diff --cached --name-only)"
# bench/ isn't used by any cargo test, so benchmark-only commits skip too.
if [[ -z "$changed" ]] || ! grep -qvE '^docs/|^bench/|\.md$|^scripts/(precommit-full|install-hooks)\.sh$' <<<"$changed"; then
    echo "pre-commit: only docs, benchmarks or hook scripts changed, skipping the full suites"
    exit 0
fi

snapshot="$(mktemp -d /tmp/next-lang-precommit.XXXXXX)"
trap 'rm -rf -- "$snapshot"' EXIT
git checkout-index -a -f --prefix="$snapshot/"
run_rust=0
if grep -qE '^compiler/src/|^compiler/Cargo\.toml$|^compiler/build\.rs$' <<<"$changed"; then
    run_rust=1
fi
if (( run_rust )); then
    echo "pre-commit: running the selfhost and Rust suites on the staged tree in $snapshot (limit 1 hour) ..."
else
    echo "pre-commit: running the selfhost suite on the staged tree in $snapshot (limit 1 hour) ..."
fi

cd "$snapshot"
ulimit -v 8000000
export CARGO_TARGET_DIR="$HOME/.cache/next-lang/target-precommit"
start=$(date +%s)
status=0
suite_command='NLC_FRONTEND=selfhost cargo test --offline --release -q'
if (( run_rust )); then
    suite_command+=' && NLC_FRONTEND=rust cargo test --offline --release -q'
fi
timeout --foreground 3600 bash -c "$suite_command" || status=$?
elapsed=$(( $(date +%s) - start ))
if (( status == 124 )); then
    echo "pre-commit: FAILED: the full suites passed the one-hour limit (${elapsed} s)"
elif (( status != 0 )); then
    echo "pre-commit: FAILED: the full suites failed (status $status, ${elapsed} s)"
else
    echo "pre-commit: selected suites passed in ${elapsed} s"
fi
exit "$status"
