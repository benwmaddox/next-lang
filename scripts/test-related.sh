#!/usr/bin/env bash
# Run the Python tests related to the files you changed (uncommitted changes plus the commits since main), in seconds to
# a minute instead of the full suite's 3 to 4 minutes. Pass test names (e.g. `jobs http_jobs`) to run exactly those.
# The pre-commit hook still runs everything; this is the working loop. Usage: scripts/test-related.sh [test_name...]
set -euo pipefail
cd "$(dirname "$0")/.."
tests=("$@")
if [[ ${#tests[@]} -eq 0 ]]; then
    changed="$( { git diff --name-only HEAD; git diff --name-only origin/main...HEAD 2>/dev/null; } | sort -u)"
    add() { for t in "$@"; do [[ " ${tests[*]:-} " == *" $t "* ]] || tests+=("$t"); done; }
    while IFS= read -r file; do
        case "$file" in
            tests/py/test_*.py) name="${file##*/test_}"; add "${name%.py}" ;;
            runtime/nl_runtime.c) add jobs mailbox http_jobs http_echo http_headers threads web cache ticks utf8 ;;
            selfhost/jobs.nl|selfhost/stack_estimates.nl|selfhost/limits.nl) add stack_estimates stack_budget jobs ;;
            selfhost/mailbox*.nl|selfhost/mailboxes.nl|selfhost/mailbox_ops.nl) add mailbox mailbox_language jobs ;;
            selfhost/db_rows.nl|selfhost/c_runtime.nl) add db_rows db_query db_text db_params query_check ;;
            selfhost/interpolation.nl|selfhost/format_text.nl|selfhost/text*.nl) add interpolation text methods ;;
            tools/*|apps/campfire/*|bench/web/*.svc|bench/web/*.tpl) add services templates campfire web ;;
            scripts/nlc|scripts/nlc.ps1|docs/*|AGENTS.md) add docs cli ;;
            selfhost/*|core/*) add friction methods checks ir_shape ;;
        esac
    done <<< "$changed"
fi
if [[ ${#tests[@]} -eq 0 ]]; then echo "test-related: nothing under tests/py maps to the changed files"; exit 0; fi
export NLC_SELFHOST="${NLC_SELFHOST:-$(python3 scripts/build-selfhost-cached.py)}"
failed=0
for t in "${tests[@]}"; do
    [[ -f "tests/py/test_$t.py" ]] || { echo "test-related: no tests/py/test_$t.py" >&2; failed=1; continue; }
    if output="$(python3 -W ignore -m unittest discover -s tests/py -p "test_$t.py" 2>&1)"; then
        echo "ok    $t"
    else
        echo "FAIL  $t"; echo "$output" | tail -25; failed=1
    fi
done
exit $failed
