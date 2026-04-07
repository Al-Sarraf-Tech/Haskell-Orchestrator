#!/usr/bin/env bash
set -euo pipefail

# Enforce Orchestrator scan across all Al-Sarraf-Tech repos.
# Creates a PR in each repo that adds an orchestrator-scan workflow.
#
# Usage: enforce-across-repos.sh [--dry-run]

DRY_RUN="${1:-}"
ORG="Al-Sarraf-Tech"
SKIP_REPOS="Haskell-Orchestrator Haskell-Orchestrator-Business Haskell-Orchestrator-Enterprise"
WORKFLOW_CONTENT='name: Orchestrator Scan

on:
  push:
    branches: [main]
    paths:
      - ".github/workflows/**"
  pull_request:
    branches: [main]
    paths:
      - ".github/workflows/**"

jobs:
  orchestrator:
    uses: Al-Sarraf-Tech/Haskell-Orchestrator/.github/workflows/orchestrator-scan.yml@v4.0.0
    with:
      fail-on: error
'

echo "Enforcing Orchestrator scan across $ORG repos"
echo "=============================================="

repos=$(gh repo list "$ORG" --limit 50 --json name --jq '.[].name')

for repo in $repos; do
    # Skip orchestrator repos (they have their own self-check)
    if echo "$SKIP_REPOS" | grep -qw "$repo"; then
        echo "SKIP: $repo (orchestrator repo)"
        continue
    fi

    # Check if repo has workflows
    has_wf=$(gh api "repos/$ORG/$repo/contents/.github/workflows" --jq 'length' 2>/dev/null || echo "0")
    if [ "$has_wf" = "0" ] || [ -z "$has_wf" ]; then
        echo "SKIP: $repo (no workflows)"
        continue
    fi

    # Check if already has orchestrator scan
    has_scan=$(gh api "repos/$ORG/$repo/contents/.github/workflows/orchestrator-scan.yml" 2>/dev/null && echo "yes" || echo "no")
    if [ "$has_scan" = "yes" ]; then
        echo "SKIP: $repo (already has orchestrator scan)"
        continue
    fi

    echo "ADD:  $repo"

    if [ "$DRY_RUN" = "--dry-run" ]; then
        continue
    fi

    # Clone, add workflow, create PR
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    gh repo clone "$ORG/$repo" "$tmpdir/$repo" -- --depth 1 2>/dev/null
    mkdir -p "$tmpdir/$repo/.github/workflows"
    echo "$WORKFLOW_CONTENT" > "$tmpdir/$repo/.github/workflows/orchestrator-scan.yml"

    cd "$tmpdir/$repo"
    git checkout -b add-orchestrator-scan
    git add .github/workflows/orchestrator-scan.yml
    git commit -m "ci: add Orchestrator workflow scan (v4.0.0)

Enforces GitHub Actions workflow best practices via 36 policy rules.
See: https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator"

    git push origin add-orchestrator-scan 2>/dev/null

    gh pr create \
        --title "ci: add Orchestrator workflow scan" \
        --body "Adds automated workflow scanning via [Haskell Orchestrator v4.0.0](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator).

Scans \`.github/workflows/\` on push and PR to main. Fails CI on Error or Critical findings.

**36 rules** covering: security, performance, cost, style, structure." \
        --repo "$ORG/$repo" 2>/dev/null || echo "  (PR creation failed for $repo)"

    cd -
    rm -rf "$tmpdir"
    trap - EXIT

    echo "  PR created for $repo"
done

echo ""
echo "Done."
