# Haskell Orchestrator — Deployment Guide

Version 3.0.3 | Operator reference for installation, CI integration, and governance setup.

---

## 1. Binary Installation

### Linux (x86-64)

```bash
# Download pre-built binary from GitHub Releases
curl -fsSL https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/releases/latest/download/orchestrator-linux-x86_64 \
  -o /usr/local/bin/orchestrator
chmod +x /usr/local/bin/orchestrator

# Verify installation
orchestrator --version
orchestrator doctor
```

Using the install script (verifies SHA-256 checksum):

```bash
curl -fsSL https://raw.githubusercontent.com/Al-Sarraf-Tech/Haskell-Orchestrator/main/scripts/install.sh | bash
```

Uninstall:

```bash
bash scripts/uninstall.sh
```

### Build from Source

Requires GHC 9.6.7 and Cabal 3.10+. On Fedora:

```bash
# GHC via ghcup (system profile.d, not ~/.ghcup/env)
export PATH=/opt/haskell/.ghcup/bin:$PATH

git clone https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator.git
cd Haskell-Orchestrator
cabal build exe:orchestrator -O2
cp "$(cabal list-bin orchestrator)" /usr/local/bin/orchestrator
```

---

## 2. Container Deployment

### Build Image

```bash
# Builds a multi-stage image (Haskell build + debian:bookworm-slim runtime)
podman build -t orchestrator:latest -f Containerfile .
# or
docker build -t orchestrator:latest -f Containerfile .
```

The runtime image contains only the stripped binary + CA certificates. No Haskell runtime required.

### Run Container

```bash
# Scan a local repository
podman run --rm -v /path/to/repo:/repo:ro orchestrator:latest scan /repo

# With config override
podman run --rm \
  -v /path/to/repo:/repo:ro \
  -v /path/to/.orchestrator.yml:/home/orchestrator/.orchestrator.yml:ro \
  orchestrator:latest scan /repo --fail-on error
```

### Pull Published Image (GHCR)

```bash
podman pull ghcr.io/al-sarraf-tech/haskell-orchestrator:latest
```

Images are published on every tagged release via `release-haskell.yml`.

---

## 3. CI Integration Patterns

### GitHub Actions

```yaml
# .github/workflows/orchestrator-scan.yml
name: Workflow Hygiene

on: [push, pull_request]

jobs:
  scan:
    runs-on: [self-hosted, Linux, X64, haskell, unified-all]
    steps:
      - uses: actions/checkout@v4

      - name: Install orchestrator
        run: |
          curl -fsSL https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/releases/latest/download/orchestrator-linux-x86_64 \
            -o /usr/local/bin/orchestrator
          chmod +x /usr/local/bin/orchestrator

      - name: Scan workflows
        run: orchestrator scan .github/workflows/ --fail-on error

      - name: SARIF upload
        if: always()
        run: orchestrator scan .github/workflows/ --sarif > results.sarif

      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: results.sarif
```

Using the pre-built enterprise binary (instant scan, no build step):

```yaml
      - name: Run orchestrator-enterprise scan
        run: |
          orchestrator-enterprise scan .github/workflows/ --fail-on error
```

### GitLab CI

```yaml
orchestrator-scan:
  stage: test
  image: ghcr.io/al-sarraf-tech/haskell-orchestrator:latest
  script:
    - orchestrator scan .github/workflows/ --fail-on error --json > findings.json
  artifacts:
    paths:
      - findings.json
    when: always
```

### Jenkins

```groovy
stage('Workflow Hygiene') {
    steps {
        sh 'orchestrator scan .github/workflows/ --fail-on error'
    }
    post {
        always {
            sh 'orchestrator scan .github/workflows/ --sarif > orchestrator.sarif || true'
            recordIssues tools: [sarif(pattern: 'orchestrator.sarif')]
        }
    }
}
```

---

## 4. Configuration (.orchestrator.yml)

Place `.orchestrator.yml` in the repository root. CLI flags override file settings.

```yaml
scan:
  targets:
    - .                    # Scan from repo root
  exclude:
    - vendor/
    - third_party/
  max_depth: 10
  follow_symlinks: false

policy:
  pack: standard           # standard | extended
  min_severity: info       # info | warning | error | critical
  disabled: []             # e.g. [NAME-001, NAME-002]

output:
  format: text             # text | json | sarif | markdown
  verbose: false
  color: true

resources:
  jobs: 4                  # parallel workers (1-32)
  profile: safe            # safe | balanced | fast
```

Key CLI flags that override config:

| Flag | Effect |
|---|---|
| `--fail-on SEVERITY` | Exit 1 if any finding >= SEVERITY |
| `--tags TAG` | Filter rules by tag (security, performance, cost, style, structure) |
| `--baseline FILE` | Suppress findings present in a saved baseline |
| `--json` / `--sarif` / `--markdown` | Output format |
| `--jobs N` | Parallelism override |

Save a baseline to suppress known issues during incremental adoption:

```bash
orchestrator baseline .github/workflows/  # saves .orchestrator-baseline.json
orchestrator scan . --baseline .orchestrator-baseline.json --fail-on error
```

---

## 5. Governance Setup (Enterprise)

Enterprise-specific. Requires `orchestrator-enterprise` binary.

### Initial Setup

```bash
# Initialise org-level governance config
orchestrator-enterprise init --org Al-Sarraf-Tech

# Verify connectivity and config
orchestrator-enterprise doctor

# Dry-run governance enforcement (no changes applied)
orchestrator-enterprise governance enforce --org Al-Sarraf-Tech --dry-run
```

### Policy Enforcement Levels

Policies are assigned one of three enforcement levels:

| Level | Behaviour |
|---|---|
| `Advisory` | Findings reported; no exit-code failure |
| `Mandatory` | Findings cause exit 1; CI gate fails |
| `Blocking` | Findings block merge (requires GitHub branch protection integration) |

Policy scoping — apply rules to:

- `AllRepos` — entire organisation
- `RepoPattern` — glob match (e.g. `*-service`)
- `SpecificRepos` — explicit list

### Audit Trail

```bash
# Query audit log
orchestrator-enterprise audit --actor jalsarraf --severity error --since 2026-01-01

# Export audit evidence
orchestrator-enterprise audit export --format json > audit-2026-Q1.json
orchestrator-enterprise audit export --format csv  > audit-2026-Q1.csv
```

### Compliance Artifacts

```bash
# Generate SOC 2 Type II compliance artifact
orchestrator-enterprise compliance --framework soc2 --output soc2-evidence/

# Generate HIPAA compliance artifact
orchestrator-enterprise compliance --framework hipaa --output hipaa-evidence/

# Full org compliance export (admin only)
orchestrator-enterprise admin export --org Al-Sarraf-Tech --output compliance-bundle/
```

### RBAC Roles

| Role | Capabilities |
|---|---|
| `PolicyAdmin` | Full governance config, enforcement, policy CRUD |
| `Auditor` | Read-only audit log access, export |
| `Operator` | Scan, enforce, report |
| `Viewer` | Scan results only |

### Risk Scoring

```bash
# Per-repo risk scores (0-100) with org heatmap
orchestrator-enterprise risk --org Al-Sarraf-Tech

# Drift detection against saved baseline
orchestrator-enterprise drift --org Al-Sarraf-Tech --baseline ./baseline.json
```

### Webhook Notifications

Configure in `.orchestrator.yml` under Enterprise:

```yaml
notifications:
  slack:
    webhook_url: "https://hooks.slack.com/services/..."
    channel: "#ci-alerts"
    on: [error, critical]
  pagerduty:
    routing_key: "..."
    on: [critical]
```

---

## 6. Verification

After any installation or upgrade:

```bash
orchestrator doctor           # environment diagnostics
orchestrator verify           # config validity check
orchestrator demo             # self-contained smoke test (no external access)
bash scripts/verify-release.sh   # full release gate (requires source checkout)
```

Pre-push gate (mandatory per CLAUDE.md):

```bash
orchestrator-enterprise scan .github/workflows/ --fail-on error
```
