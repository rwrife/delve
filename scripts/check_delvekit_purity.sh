#!/usr/bin/env bash
# DelveKit is a pure domain package. UIKit/SpriteKit belong to the app and
# GRDB belongs to DelveStore; importing any of them here would break Linux
# testability and layer boundaries.
set -euo pipefail

cd "$(dirname "$0")/.."
source_root="Packages/DelveKit/Sources"

if grep -RnE --include='*.swift' '^[[:space:]]*import[[:space:]]+(UIKit|SpriteKit|GRDB)([[:space:]]|$)' "$source_root"; then
  echo "DelveKit purity gate: FAIL (UIKit/SpriteKit/GRDB import found)" >&2
  exit 1
fi

echo "DelveKit purity gate: PASS (no UIKit/SpriteKit/GRDB imports)"
