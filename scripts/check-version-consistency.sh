#!/usr/bin/env bash
set -euo pipefail

# Verify version consistency across all artifacts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
PASS=0
FAIL=0

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; PASS=$((PASS + 1)); }
fail_msg() { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAIL=$((FAIL + 1)); }

echo "Version Consistency Check"
echo "========================="

# Extract version from cabal file
CABAL_VER=$(grep "^version:" "$REPO_DIR"/*.cabal | head -1 | awk '{print $2}')
echo "Cabal version: $CABAL_VER"

# Check CHANGELOG mentions this version (match x.y.z.w or x.y.z)
SHORT_VER=$(echo "$CABAL_VER" | sed 's/\.0$//')
if grep -qE "\[${CABAL_VER}\]|\[${SHORT_VER}\]" "$REPO_DIR/CHANGELOG.md" 2>/dev/null; then
  pass "CHANGELOG.md mentions version $CABAL_VER (or $SHORT_VER)"
else
  fail_msg "CHANGELOG.md does not mention version $CABAL_VER or $SHORT_VER"
fi

# Check cabal version is valid semver-ish (x.y.z.w)
if echo "$CABAL_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  pass "Cabal version format is valid: $CABAL_VER"
else
  fail_msg "Invalid cabal version format: $CABAL_VER"
fi

echo
echo "========================="
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf "${RED}VERSION CHECK FAILED${NC}\n"
  exit 1
else
  printf "${GREEN}VERSION CHECK PASSED${NC}\n"
fi
