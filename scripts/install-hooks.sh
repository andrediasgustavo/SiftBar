#!/usr/bin/env bash
set -euo pipefail

# Installs the local pre-commit hook that runs scripts/check.sh.
#
#   ./scripts/install-hooks.sh
#
# Skip it for one commit with:
#   SIFTBAR_SKIP_HOOK=1 git commit ...

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/.git/hooks/pre-commit"

if [ ! -d "$ROOT/.git" ]; then
    echo "Not a git checkout: $ROOT" >&2
    exit 1
fi

cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${SIFTBAR_SKIP_HOOK:-0}" = "1" ]; then
    echo "pre-commit: skipped (SIFTBAR_SKIP_HOOK=1)"
    exit 0
fi

exec "$(git rev-parse --show-toplevel)/scripts/check.sh"
EOF

chmod +x "$HOOK"
echo "Installed $HOOK"
