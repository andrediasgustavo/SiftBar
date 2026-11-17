#!/usr/bin/env bash
set -euo pipefail

# Muter exits successfully even when mutants survive. This makes the manual
# mutation job a real gate: any survivor in the selected safety files fails.
REPORT="${1:-muter-report.txt}"

if [ ! -f "$REPORT" ]; then
    echo "Mutation report not found: $REPORT" >&2
    exit 1
fi

if ! grep -q "mutant" "$REPORT"; then
    echo "Mutation report has no mutant results." >&2
    exit 1
fi

if grep -q "mutant survived" "$REPORT"; then
    echo "Mutation gate failed: at least one mutant survived." >&2
    grep "mutant survived" "$REPORT" >&2
    exit 1
fi

if ! grep -q "mutant killed" "$REPORT"; then
    echo "Mutation gate failed: no killed mutants in the report." >&2
    exit 1
fi

echo "Mutation gate OK: every reported mutant was killed."
