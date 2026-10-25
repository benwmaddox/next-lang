#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" != "--update" ]]; then
    printf 'usage: scripts/update-parse-dumps.sh --update\n' >&2
    exit 3
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target_dir=${CARGO_TARGET_DIR:-"$HOME/.cache/next-lang/target"}
cd "$repo_root"
CARGO_TARGET_DIR="$target_dir" cargo build --bin nlc
nlc_bin="$target_dir/debug/nlc"

write_package_dumps() {
    local category=$1
    local name=$2
    local package=$3
    local output_dir="tests/parse/dumps/$category"
    local dump="$output_dir/$name.dump"
    local tokens="$output_dir/$name.tokens"
    local tree="$output_dir/$name.tree"
    local error="$output_dir/$name.stderr"
    local exit_file="$output_dir/$name.exit"
    local temporary="$output_dir/.$name.tmp"
    local status

    case "$category:$name" in
        run:t19_expression_plus_1000|\
        run:t19_expression_and_1000|\
        run:t19_expression_call_1000|\
        run:t19_expression_if_300|\
        run:t19_expression_paren_1000|\
        run:t12_sort_specialization_limit|\
        cases:long_line)
            # These fixtures are compared against two live parses by parse_dump.rs.
            rm -f "$temporary" "$dump" "$tokens" "$tree" "$error" "$exit_file"
            return
            ;;
    esac

    mkdir -p "$output_dir"
    if "$nlc_bin" parse "$package" --tokens --tree >"$temporary" 2>"$error"; then
        mv "$temporary" "$dump"
        rm -f "$tokens" "$tree"
        rm -f "$error" "$exit_file"
    else
        status=$?
        rm -f "$temporary" "$dump" "$tokens" "$tree"
        printf '%s\n' "$status" >"$exit_file"
    fi
}

for category in run test; do
    for package in "tests/$category"/*; do
        [[ -d "$package" ]] || continue
        write_package_dumps "$category" "${package##*/}" "$package"
    done
done

for package in tests/parse/cases/*; do
    [[ -d "$package" ]] || continue
    write_package_dumps cases "${package##*/}" "$package"
done

while IFS= read -r -d '' dump_path; do
    size=$(wc -c <"$dump_path")
    if ((size > 100000)); then
        printf 'parse dump exceeds 100 KB: %s (%s bytes)\n' "$dump_path" "$size" >&2
        exit 1
    fi
done < <(find tests/parse/dumps -type f \( -name '*.dump' -o -name '*.tokens' -o -name '*.tree' \) -print0)
