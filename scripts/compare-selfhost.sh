#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
reference=""
selfhost=""
tokens_mode=0
parse_mode=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tokens)
            tokens_mode=1
            shift
            ;;
        --parse)
            parse_mode=1
            shift
            ;;
        --reference)
            [[ $# -ge 2 ]] || { echo "missing value for --reference" >&2; exit 2; }
            reference="$2"
            shift 2
            ;;
        --selfhost)
            [[ $# -ge 2 ]] || { echo "missing value for --selfhost" >&2; exit 2; }
            selfhost="$2"
            shift 2
            ;;
        *)
            echo "unknown harness option: $1" >&2
            exit 2
            ;;
    esac
done
if [[ $tokens_mode == $parse_mode || -z "$reference" || -z "$selfhost" ]]; then
    echo "usage: scripts/compare-selfhost.sh (--tokens | --parse) --reference <nlc> --selfhost <selfhost>" >&2
    exit 2
fi
if [[ ! -x "$reference" || ! -x "$selfhost" ]]; then
    echo "reference and self-hosted executables must both be executable" >&2
    exit 2
fi

work="$(mktemp -d "$repo_root/.selfhost-compare.XXXXXX")"
keep_work=0
cleanup() {
    if [[ $keep_work == 1 ]]; then
        echo "comparison artifacts retained at ${work#$repo_root/}" >&2
    else
        python3 - "$work" <<'PY'
from pathlib import Path
import shutil
shutil.rmtree(Path(__import__("sys").argv[1]))
PY
    fi
}
trap cleanup EXIT

mkdir -p "$work/generated"
if [[ $parse_mode == 1 ]]; then
    python3 "$repo_root/scripts/selfhost-adversarial-cases.py" "$repo_root" "$work/generated" --parse
else
    python3 "$repo_root/scripts/selfhost-adversarial-cases.py" "$repo_root" "$work/generated"
fi
bench_relative="${work#$repo_root/}/benchmark"
if [[ $parse_mode == 1 ]]; then
    "$repo_root/scripts/gen-bench-corpus.sh" "$bench_relative" --parse
else
    "$repo_root/scripts/gen-bench-corpus.sh" "$bench_relative"
fi

reference_stdout="$work/reference.stdout"
reference_stderr="$work/reference.stderr"
selfhost_stdout="$work/selfhost.stdout"
selfhost_stderr="$work/selfhost.stderr"
corpus_count=0
directed_count=0
fuzz_count=0
parser_mutation_count=0
benchmark_count=0
current_case=""

first_difference() {
    local label="$1"
    local left="$2"
    local right="$3"
    python3 - "$label" "$left" "$right" <<'PY'
import sys

label, left_path, right_path = sys.argv[1:]
offset = 0
with open(left_path, "rb") as left, open(right_path, "rb") as right:
    while True:
        a = left.read(65536)
        b = right.read(65536)
        common = min(len(a), len(b))
        for index in range(common):
            if a[index] != b[index]:
                print(f"first {label} difference at byte {offset + index}: reference=0x{a[index]:02x}, selfhost=0x{b[index]:02x}")
                raise SystemExit
        if len(a) != len(b):
            left_byte = a[common] if common < len(a) else None
            right_byte = b[common] if common < len(b) else None
            print(f"first {label} difference at byte {offset + common}: reference={left_byte!r}, selfhost={right_byte!r} (lengths differ)")
            raise SystemExit
        if not a:
            print(f"{label} differs, but the first differing byte was not found")
            raise SystemExit
        offset += common
PY
}

fail_case() {
    local reason="$1"
    keep_work=1
    echo "selfhost comparison failed for $current_case: $reason" >&2
    if [[ "$current_case" == *"/parser-fuzz/"* ]]; then
        echo "parser mutation seed: $(cat "$work/generated/parser-fuzz-seed.txt")" >&2
        echo "failing input: $current_case/main.nl" >&2
    elif [[ "$current_case" == *"/fuzz/"* ]]; then
        echo "mutation seed: $(cat "$work/generated/fuzz-seed.txt")" >&2
        echo "failing input: $current_case/main.nl" >&2
    fi
    if [[ -f "$reference_stdout" && -f "$selfhost_stdout" ]] && ! cmp -s "$reference_stdout" "$selfhost_stdout"; then
        first_difference stdout "$reference_stdout" "$selfhost_stdout" >&2
    fi
    if [[ -f "$reference_stderr" && -f "$selfhost_stderr" ]] && ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
        first_difference stderr "$reference_stderr" "$selfhost_stderr" >&2
        echo "reference stderr:" >&2
        head -c 1000 "$reference_stderr" >&2
        echo >&2
        echo "selfhost stderr:" >&2
        head -c 1000 "$selfhost_stderr" >&2
        echo >&2
    fi
    exit 1
}

compare_package() {
    local package="$1"
    local category="$2"
    current_case="$package"
    local command="lex"
    local flag_sets=("")
    if [[ $parse_mode == 1 ]]; then
        command="parse"
        if [[ "$category" == "parser-mutation" ]]; then
            flag_sets=("--tree")
        elif [[ "$package" == *"parser_node_limit_"* || "$package" == *"parser_work_limit_"* ]]; then
            flag_sets=("")
        else
            flag_sets=("" "--tokens" "--tree" "--tokens --tree")
        fi
    fi
    for flags in "${flag_sets[@]}"; do
        current_case="$package ($command${flags:+ $flags})"
        local reference_status=0
        local selfhost_status=0
        local -a flag_args=()
        if [[ -n "$flags" ]]; then
            read -r -a flag_args <<< "$flags"
        fi
        set +e
        "$reference" "$command" "$package" "${flag_args[@]}" >"$reference_stdout" 2>"$reference_stderr"
        reference_status=$?
        "$selfhost" "$command" "$package" "${flag_args[@]}" >"$selfhost_stdout" 2>"$selfhost_stderr"
        selfhost_status=$?
        set -e

        if [[ $reference_status != $selfhost_status ]]; then
            fail_case "exit status differs: reference=$reference_status selfhost=$selfhost_status"
        fi
        if ! cmp -s "$reference_stdout" "$selfhost_stdout"; then
            fail_case "stdout differs"
        fi
        if ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
            local os_error_only=0
            if [[ $reference_status == 3 ]]; then
                python3 - "$reference_stderr" "$selfhost_stderr" <<'PY' && os_error_only=1
from pathlib import Path
import re
import sys

left, right = (Path(path).read_bytes().decode("utf-8", "replace") for path in sys.argv[1:])
pattern = re.compile(r"^(nlc: tool failure: (?:cannot read package directory|cannot read package entry|cannot read source file '.*'|could not start (?:parser|lexer) thread): )(.*?) \(os error ([0-9]+)\)\n?$")
left_match = pattern.fullmatch(left)
right_match = pattern.fullmatch(right)
if left_match and right_match and left_match.group(1) == right_match.group(1) and left_match.group(3) == right_match.group(3):
    raise SystemExit(0)
raise SystemExit(1)
PY
            fi
            if [[ $os_error_only != 1 ]]; then
                fail_case "stderr differs"
            fi
        fi
    done
    case "$category" in
        corpus) corpus_count=$((corpus_count + 1)) ;;
        fuzz) fuzz_count=$((fuzz_count + 1)) ;;
        parser-mutation) parser_mutation_count=$((parser_mutation_count + 1)) ;;
        benchmark) benchmark_count=$((benchmark_count + 1)) ;;
        *) directed_count=$((directed_count + 1)) ;;
    esac
}

assert_selfhost_cli() {
    local expected_status="$1"
    local expected_stderr="$2"
    shift 2
    current_case="selfhost CLI $*"
    local status=0
    set +e
    "$selfhost" "$@" >"$selfhost_stdout" 2>"$selfhost_stderr"
    status=$?
    set -e
    if [[ $status != "$expected_status" ]]; then
        fail_case "expected CLI status $expected_status; got $status"
    fi
    if [[ -s "$selfhost_stdout" ]]; then
        fail_case "CLI rejection wrote stdout"
    fi
    printf '%s\n' "$expected_stderr" >"$reference_stderr"
    if ! cmp -s "$reference_stderr" "$selfhost_stderr"; then
        fail_case "CLI stderr did not match its specified response"
    fi
}

cd "$repo_root"
mapfile -t corpus_packages < <(
    find tests/run tests/test tests/parse/cases -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${corpus_packages[@]}"; do
    compare_package "$package" corpus
done

mapfile -t generated_packages < <(
    find "${work#$repo_root/}/generated" \
        \( -path "${work#$repo_root/}/generated/fuzz" -o -path "${work#$repo_root/}/generated/parser-fuzz" \) -prune \
        -o -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${generated_packages[@]}"; do
    compare_package "$package" directed
    if [[ "$package" == *"later_file_failure_has_no_stdout"* ]]; then
        if [[ -s "$reference_stdout" || -s "$selfhost_stdout" ]]; then
            fail_case "a later-file lexer failure produced partial stdout"
        fi
    fi
done

if [[ $parse_mode == 1 ]]; then
    mapfile -t parser_fuzz_packages < <(
        find "${work#$repo_root/}/generated/parser-fuzz" -type f -name '*.nl' -printf '%h\n' | sort -u
    )
    for package in "${parser_fuzz_packages[@]}"; do
        compare_package "$package" parser-mutation
    done
fi

mapfile -t fuzz_packages < <(
    find "${work#$repo_root/}/generated/fuzz" -type f -name '*.nl' -printf '%h\n' | sort -u
)
for package in "${fuzz_packages[@]}"; do
    compare_package "$package" fuzz
done

if [[ $tokens_mode == 1 ]]; then
    assert_selfhost_cli 3 "nlc: tool failure: not implemented yet" lex tests/run/arithmetic --tree
    assert_selfhost_cli 3 "nlc: tool failure: not implemented yet" lex tests/run/arithmetic --tokens --tree
    assert_selfhost_cli 3 "usage: nlc run selfhost -- lex <package> [--tokens] [--tree]" lex tests/run/arithmetic --tokens --tokens
    assert_selfhost_cli 3 "usage: nlc run selfhost -- lex <package> [--tokens] [--tree]" lex tests/run/arithmetic --unknown
else
    assert_selfhost_cli 3 "usage: nlc run selfhost -- parse <package> [--tokens] [--tree]" parse tests/run/arithmetic --tokens --tokens
    assert_selfhost_cli 3 "usage: nlc run selfhost -- parse <package> [--tokens] [--tree]" parse tests/run/arithmetic --unknown
fi

compare_package "$bench_relative" benchmark
if [[ $parse_mode == 1 ]]; then
    "$reference" parse "$bench_relative" --tokens >"$reference_stdout"
fi
benchmark_rows=$(($(wc -l < "$reference_stdout") - 13))
benchmark_bytes=$(du -b "$work/benchmark"/*.nl | awk '{total += $1} END {print total + 0}')
benchmark_source_bytes=$(du -b "$work/benchmark"/bench-00.nl | awk '{print $1 + 0}')
benchmark_max_file_bytes=$(stat -c %s "$work/benchmark/bench-00.nl")
token_live_bytes=$((benchmark_rows * 20))
file_live_bytes=$((13 * 8159))
directory_live_bytes=$((13 * 16396))
data_live_estimate=$((benchmark_source_bytes * 14 + token_live_bytes + file_live_bytes + directory_live_bytes + 1048576))

reference_time="$work/reference.time"
selfhost_time="$work/selfhost.time"
if [[ $parse_mode == 1 ]]; then
    /usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$reference_time" "$reference" parse "$bench_relative" --tokens --tree >/dev/null
    /usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$selfhost_time" "$selfhost" parse "$bench_relative" --tokens --tree >/dev/null
    "$reference" inspect stacks selfhost >"$work/stack-report"
    data_reservation=$(awk '/data stack reservation:/ {print $4; exit}' "$work/stack-report")
    echo "selfhost parser comparison passed"
else
    /usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$reference_time" "$reference" lex "$bench_relative" >/dev/null
    /usr/bin/time -f 'elapsed_seconds=%e max_rss_kib=%M' -o "$selfhost_time" "$selfhost" lex "$bench_relative" >/dev/null
    echo "selfhost lexer comparison passed"
fi
echo "corpus packages: $corpus_count"
echo "directed and limit cases: $directed_count"
echo "byte mutations: $fuzz_count (seed $(cat "$work/generated/fuzz-seed.txt"))"
if [[ $parse_mode == 1 ]]; then
    echo "parser tree mutations: $parser_mutation_count (seed $(cat "$work/generated/parser-fuzz-seed.txt"))"
fi
echo "benchmark: 13 files, 54,145 lines, $benchmark_bytes bytes, $benchmark_rows tokens"
echo "benchmark logical live-data high water estimate: $data_live_estimate bytes (source $benchmark_source_bytes package bytes plus $benchmark_max_file_bytes file staging, $token_live_bytes token bytes, file and directory entries, 1 MiB output buffer)"
echo "benchmark process measurements: reference $(cat "$reference_time"); selfhost $(cat "$selfhost_time")"
if [[ $parse_mode == 1 ]]; then
    echo "selfhost data-stack reservation: $data_reservation bytes; process max RSS above is the runtime touched-memory measurement"
    echo "selfhost native-stack report: $(awk '/native stack worst case:/ {print $5; exit}' "$work/stack-report") bytes worst case"
fi
