#!/usr/bin/env bash
set -euo pipefail

# Release gate script — fails if tracked/staged content contains
# prohibited terms.  Terms are built dynamically to avoid self-match.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Build terms dynamically to avoid self-triggering
T1="CLAU"
T2="DE"
T3="Anthro"
T4="pic"
TERMS="${T1}${T2}\.md|AGENTS\.md|${T1}${T2} Code|${T3}${T4}|AI-generated|Co-authored-by|Generated-by"
FAIL=0

echo "Release Gate Check"
echo "==================="

# Check tracked files (exclude this script and CI workflow files which build terms dynamically)
MATCHES=$(grep -rIl --include='*.md' --include='*.hs' --include='*.cabal' \
     -E "$TERMS" "$REPO_DIR" 2>/dev/null | grep -v '.local/' | grep -v '.git/' || true)

if [[ -n "$MATCHES" ]]; then
  printf "${RED}FAIL${NC}: Prohibited content found:\n"
  echo "$MATCHES"
  FAIL=1
fi

# Check for prohibited files
for f in "${T1}${T2}.md" AGENTS.md; do
  if [[ -f "$REPO_DIR/$f" ]]; then
    printf "${RED}FAIL${NC}: Prohibited file exists: $f\n"
    FAIL=1
  fi
done

if [[ $FAIL -eq 0 ]]; then
  printf "${GREEN}PASS${NC}: Release gate checks passed\n"
else
  exit 1
fi
