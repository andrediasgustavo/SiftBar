#!/usr/bin/env bash
set -euo pipefail

# One-time repository setting for the light branch-protection policy:
# PRs only, CI must be green, no force pushes or branch deletion. It does not
# require a code-owner approval, so a single maintainer can self-merge.
#
# Requires an authenticated GitHub CLI with admin rights:
#   gh auth login
#   ./scripts/apply-branch-protection.sh

REPO="${1:-andrediasgustavo/SiftBar}"

if ! command -v gh >/dev/null 2>&1; then
    echo "gh is required: brew install gh && gh auth login" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "gh is not authenticated: run 'gh auth login'" >&2
    exit 1
fi

echo "Applying light branch protection to $REPO main"
gh api \
    --method PUT \
    "repos/$REPO/branches/main/protection" \
    --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Build and test",
      "Scripts and app bundle",
      "UI tests (XCUITest)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": false
}
JSON

echo "Branch protection applied. Direct pushes to main are now blocked; use a PR."
