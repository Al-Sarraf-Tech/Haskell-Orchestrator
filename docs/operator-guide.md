# Operator Guide — Haskell Orchestrator Community Edition

Author: Jamal Al-Sarraf

---

## Overview

This guide covers practical integration of Haskell Orchestrator into
CI pipelines, team workflows, and day-to-day operations. It assumes the
tool is already installed. See the [Quickstart](quickstart.md) for
installation steps.

---

## CI Pipeline Integration

### GitHub Actions

Add a workflow that runs Haskell Orchestrator as a check on pull requests
that modify workflow files:

```yaml
name: Workflow Lint
on:
  pull_request:
    paths:
      - '.github/workflows/**'

permissions:
  contents: read

jobs:
  orchestrator-scan:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Install Haskell Orchestrator
        run: |
          # Download pre-built binary from releases
          curl -sL https://github.com/jalsarraf0/Haskell-Orchestrator/releases/latest/download/orchestrator-linux-x86_64 -o orchestrator
          chmod +x orchestrator

      - name: Scan workflows
        run: ./orchestrator scan .

      - name: Check for errors
        run: |
          ERRORS=$(./orchestrator --json scan . | jq '[.findings[] | select(.severity == "Error" or .severity == "Critical")] | length')
          if [ "$ERRORS" -gt 0 ]; then
            echo "Found $ERRORS error-level findings. Failing check."
            exit 1
          fi
```

### Alternative: Build from Source in CI

If pre-built binaries are not available, build from source:

```yaml
      - name: Setup Haskell
        uses: haskell-actions/setup@v2
        with:
          ghc-version: '9.6.7'
          cabal-version: '3.14'

      - name: Build Orchestrator
        run: |
          git clone https://github.com/jalsarraf0/Haskell-Orchestrator.git /tmp/orchestrator
          cd /tmp/orchestrator
          cabal update
          cabal build exe:orchestrator
          cabal install exe:orchestrator --install-method=copy --overwrite-policy=always --installdir=$HOME/.local/bin

      - name: Scan
        run: orchestrator scan .
```

### GitLab CI

```yaml
workflow-scan:
  stage: lint
  image: haskell:9.6
  script:
    - cabal update
    - cabal install orchestrator
    - orchestrator scan .
  rules:
    - changes:
        - .github/workflows/*
```

### Jenkins

```groovy
stage('Workflow Scan') {
    steps {
        sh 'orchestrator scan .'
        sh '''
            ERRORS=$(orchestrator --json scan . | jq '[.findings[] | select(.severity == "Error" or .severity == "Critical")] | length')
            if [ "$ERRORS" -gt 0 ]; then
                echo "Error-level findings detected"
                exit 1
            fi
        '''
    }
}
```

---

## Gating Strategies

### Strict: Fail on Any Error

Fail the pipeline if any Error or Critical finding exists:

```bash
ERRORS=$(orchestrator --json scan . | jq '[.findings[] | select(.severity == "Error" or .severity == "Critical")] | length')
[ "$ERRORS" -eq 0 ] || exit 1
```

### Moderate: Fail on Critical Only

Allow errors and warnings but fail on critical findings:

```bash
CRITICAL=$(orchestrator --json scan . | jq '[.findings[] | select(.severity == "Critical")] | length')
[ "$CRITICAL" -eq 0 ] || exit 1
```

### Advisory: Report Only

Run the scan and display findings without failing the pipeline. Useful
during initial rollout:

```bash
orchestrator scan .
# Always exit 0 — findings are informational
```

### Threshold-Based

Fail if total findings exceed a threshold:

```bash
TOTAL=$(orchestrator --json scan . | jq '.findings | length')
THRESHOLD=10
if [ "$TOTAL" -gt "$THRESHOLD" ]; then
    echo "Finding count ($TOTAL) exceeds threshold ($THRESHOLD)"
    exit 1
fi
```

---

## Configuration Tuning

### Starting Configuration

Begin with minimal configuration and tighten over time:

```yaml
# .orchestrator.yml — initial rollout
scan:
  targets: ["."]
  exclude: []
  max_depth: 10

policy:
  pack: standard
  min_severity: error      # Start with errors only
  disabled: []

output:
  format: text
  verbose: false
  color: true

resources:
  jobs: 1
  profile: safe
```

### Tightening Over Time

Phase 1 (week 1-2): Report errors only, advisory mode.

```yaml
policy:
  min_severity: error
```

Phase 2 (week 3-4): Include warnings, still advisory.

```yaml
policy:
  min_severity: warning
```

Phase 3 (month 2): Gate on errors, report warnings.

```bash
# CI script
orchestrator scan .  # Report all findings
# Gate on errors only
orchestrator --json scan . | jq -e '[.findings[] | select(.severity == "Error" or .severity == "Critical")] | length == 0'
```

Phase 4 (month 3+): Gate on warnings too.

```yaml
policy:
  min_severity: warning
```

```bash
orchestrator --json scan . | jq -e '.findings | length == 0'
```

### Excluding Paths

Exclude deprecated, generated, or third-party workflow files:

```yaml
scan:
  exclude:
    - ".github/workflows/deprecated/"
    - ".github/workflows/generated-*"
    - ".github/workflows/vendor/"
```

### Disabling Rules

Disable rules that do not apply to your environment:

```yaml
policy:
  disabled:
    - NAME-001    # We use a different naming convention
    - RUN-001     # We intentionally use self-hosted runners
    - TRIG-001    # Wildcard triggers are acceptable for our use case
```

---

## Team Adoption

### Step 1: Baseline Scan

Run a scan against all repositories to establish a baseline:

```bash
for repo in /path/to/repos/*; do
    echo "=== $(basename "$repo") ==="
    orchestrator scan "$repo" || true
done
```

### Step 2: Triage Findings

Categorise findings into:
- **Fix immediately**: Error and Critical severity, especially SEC-002
  (secrets in run steps) and PERM-002 (write-all permissions)
- **Fix in next sprint**: Warning severity items like unpinned actions
  and missing timeouts
- **Track as tech debt**: Info severity items like naming conventions

### Step 3: Establish CI Gate

Add the scan to CI in advisory mode first. Let the team see findings
for 1-2 weeks before enabling hard gates.

### Step 4: Fix Forward

Address findings as part of normal development. When touching a workflow
file, fix any findings in that file. This prevents the backlog from
growing without requiring a dedicated cleanup sprint.

### Step 5: Periodic Review

Run a full scan weekly or monthly to detect drift. Compare findings
against the baseline to track progress:

```bash
# Save baseline
orchestrator --json scan . > findings-baseline.json

# Later, compare
orchestrator --json scan . > findings-current.json
diff <(jq -r '.findings[].rule_id' findings-baseline.json | sort | uniq -c | sort -rn) \
     <(jq -r '.findings[].rule_id' findings-current.json | sort | uniq -c | sort -rn)
```

---

## Resource Profiles

| Profile | Workers | When to Use |
|---|---|---|
| safe | 1 | Default. Shared CI runners, constrained environments |
| balanced | CPU/2 | Dedicated CI runners, moderate workloads |
| fast | CPU count | Local development, large scan targets |

Override via configuration:

```yaml
resources:
  profile: balanced
```

Or via command line:

```bash
orchestrator --jobs 4 scan .
```

---

## JSON Output for Tooling

Use JSON output to integrate with other tools:

```bash
# Count findings by severity
orchestrator --json scan . | jq '[.findings[] | .severity] | group_by(.) | map({(.[0]): length}) | add'

# List unique rule IDs triggered
orchestrator --json scan . | jq '[.findings[].rule_id] | unique | .[]' -r

# Extract findings for a specific file
orchestrator --json scan . | jq '[.findings[] | select(.file | contains("ci.yml"))]'

# Generate a simple CSV
orchestrator --json scan . | jq -r '.findings[] | [.severity, .rule_id, .file, .message] | @csv'
```

---

## Troubleshooting

### "No workflows found"

- Verify the target path contains `.github/workflows/` with `.yml` or
  `.yaml` files.
- Check that `scan.exclude` patterns do not exclude the workflow directory.
- Verify `scan.max_depth` is sufficient to reach the workflows directory.

### Too Many Findings

- Start with `min_severity: error` and expand later.
- Disable rules that do not apply: `policy.disabled: [RULE_ID, ...]`.
- Use `scan.exclude` to skip deprecated or generated workflows.

### Slow Scans

- Increase worker count: `--jobs 4` or `resources.profile: balanced`.
- Exclude unnecessary paths.
- Reduce `scan.max_depth` if directory trees are deep.

### JSON Parse Errors

- Ensure you are using `--json` flag (not redirecting text output).
- Verify the output is valid JSON with `orchestrator --json scan . | jq .`.

---

## Scaling Beyond Community

When Community edition no longer meets your needs:

| Need | Solution |
|---|---|
| Batch scanning across 5+ repositories | Business edition |
| HTML/CSV reports for stakeholders | Business edition |
| Effort-based remediation prioritisation | Business edition |
| Team-specific policy rules | Business edition |
| Org-wide governance enforcement | Enterprise edition |
| Immutable audit trails | Enterprise edition |
| SOC 2 / HIPAA compliance mapping | Enterprise edition |
| Compliance artifact generation | Enterprise edition |

See the [Edition Comparison](edition-comparison.md) for full details.

---

## Recommended CI Workflow Structure

```yaml
name: Workflow Governance
on:
  pull_request:
    paths: ['.github/workflows/**']
  schedule:
    - cron: '0 9 * * 1'   # Weekly Monday scan

permissions:
  contents: read

jobs:
  scan:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Install Orchestrator
        run: |
          curl -sL "$ORCHESTRATOR_URL" -o orchestrator && chmod +x orchestrator
      - name: Scan
        run: ./orchestrator scan .
      - name: Gate
        run: |
          ERRORS=$(./orchestrator --json scan . | jq '[.findings[] | select(.severity == "Error" or .severity == "Critical")] | length')
          echo "Error-level findings: $ERRORS"
          [ "$ERRORS" -eq 0 ]
      - name: Upload findings
        if: always()
        run: ./orchestrator --json scan . > findings.json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: orchestrator-findings
          path: findings.json
```
