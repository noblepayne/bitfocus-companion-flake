#!/usr/bin/env bash
set -euo pipefail

# Script to generate missing-hashes.json for bitfocus-companion
# Uses nix to fetch the source and runs yarn-berry-fetcher on yarn.lock

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Fetching companion source..."

# Use nix to fetch the source from package.nix
SOURCE=$(nix eval --raw ".#companion.src" 2>/dev/null)

YARN_LOCK="$SOURCE/yarn.lock"

if [[ ! -f "$YARN_LOCK" ]]; then
	echo "Error: yarn.lock not found at $YARN_LOCK"
	exit 1
fi

echo "Generating missing hashes from $YARN_LOCK..."

# Generate missing hashes using yarn-berry-fetcher
nix run .#yarn-berry-fetcher-with-retries missing-hashes "$YARN_LOCK" >"$SCRIPT_DIR/missing-hashes.json"

echo "✓ Done! Updated: $SCRIPT_DIR/missing-hashes.json"
