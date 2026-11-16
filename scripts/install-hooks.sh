#!/usr/bin/env bash
set -euo pipefail

# Installs a fast local pre-commit hook: unit tests only.
#
# UI tests are intentionally not part of commit/push. They run in CI and in
# the nightly, or manually through the full gate:
#
#   ./scripts/check.sh
#
#   ./scripts/install-hooks.sh
#
# Skip the unit hook for one commit with:
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

# Fast commit gate. UI tests live in CI/nightly; run ./scripts/check.sh
# manually when you want the full local gate.
exec "$(git rev-parse --show-toplevel)/scripts/test.sh"
EOF

chmod +x "$HOOK"
echo "Installed $HOOK (unit tests only; UI runs in CI/nightly)"
