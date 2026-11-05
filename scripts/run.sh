#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"

"$ROOT/scripts/build.sh" "$CONFIG"
open "$ROOT/dist/SiftBar.app"
