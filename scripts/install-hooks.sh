#!/usr/bin/env bash
# Install the repository's git hooks (run once per clone).
set -euo pipefail
repo="$(git rev-parse --show-toplevel)"
hooks="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks"
cat > "$hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/precommit-full.sh"
EOF
chmod +x "$hooks/pre-commit"
echo "installed pre-commit hook -> scripts/precommit-full.sh"
