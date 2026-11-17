#!/usr/bin/env bash
set -euo pipefail

# SiftBar intentionally has no external Swift package dependencies. A new
# dependency (or a hallucinated package name) must be a deliberate, reviewed
# decision, not a side effect of a generated change.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if grep -Eq '\.package[[:space:]]*\(' "$ROOT/Package.swift"; then
    echo "External Swift dependencies found in Package.swift." >&2
    echo "Review the dependency explicitly before merging." >&2
    exit 1
fi

if [ -f "$ROOT/Package.resolved" ]; then
    echo "Package.resolved exists; the dependency policy expects no external packages." >&2
    exit 1
fi

echo "Dependency policy OK: no external Swift packages."
