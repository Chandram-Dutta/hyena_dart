#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version (`## [x.y.z]` heading).
# Exits non-zero when the section is missing or empty.
set -euo pipefail

version="${1:?usage: tool/release_notes.sh <version>}"

notes="$(awk -v v="$version" '
  index($0, "## [" v "]") == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' CHANGELOG.md)"

if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "No CHANGELOG.md section '## [$version]' found" >&2
  exit 1
fi

printf '%s\n' "$notes"
