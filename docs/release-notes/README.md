# Release notes

Every release ships its "What's new" text in the **GitHub release notes**,
never in the README. The README is the end-user guide only; it has no
changelog.

The Release workflow (`.github/workflows/release.yml`) uses this folder when
the file exists: `docs/release-notes/vX.Y.Z.md` becomes the release body for
tag `vX.Y.Z`. When the file is missing, notes are generated automatically
from the commit messages.

Process for a new release:

1. Write `docs/release-notes/vX.Y.Z.md` **before** pushing the `vX.Y.Z` tag:
   short user-facing bullets, no internals.
2. Bump the version, run the suite, commit, push, and push the tag.
3. The workflow publishes the release with this file as the body and appends
   the first-launch note automatically.

See `v0.4.0.md` for an example.
