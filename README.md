# Haskell Orchestrator

[![CI](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/actions/workflows/ci-haskell.yml/badge.svg)](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/actions/workflows/ci-haskell.yml)
[![Version](https://img.shields.io/badge/version-4.0.0-blue)](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Verified by Haskell Orchestrator](https://img.shields.io/badge/self--checked-36%20rules%20%7C%200%20findings-brightgreen)](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-pink?logo=github)](https://github.com/sponsors/jalsarraf0)

**Typed analysis engine for GitHub Actions workflows.**

Haskell Orchestrator parses workflow YAML into a typed domain model, evaluates
36 configurable policy rules, and produces deterministic remediation plans —
without modifying any files. It covers security, supply chain, performance,
cost, structure, and drift concerns in a single pass.

This is not a YAML linter. It understands GitHub Actions semantics:
permissions scopes, action pinning, job graph topology, matrix expansion,
environment gates, concurrency, privilege escalation vectors, and more.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Installation](#installation)
- [CI Integration](#ci-integration)
- [Rules Reference](#rules-reference)
- [Inline Suppression](#inline-suppression)
- [CLI Reference](#cli-reference)
- [Configuration](#configuration)
- [Edition Comparison](#edition-comparison)
- [Safety Model](#safety-model)
- [Development](#development)
- [Documentation](#documentation)
- [Release Integrity](#release-integrity)
- [Shell Completions](#shell-completions)
- [License](#license)

---

## Quick Start

```bash
# 1. Install (Linux x86_64)
tar xzf haskell-orchestrator-4.0.0-linux-x86_64.tar.gz
sudo cp orchestrator /usr/local/bin/

# 2. Verify the install
orchestrator demo

# 3. Scan your repository
orchestrator scan /path/to/your/repo

# 4. Scan only security rules
orchestrator scan /path/to/your/repo --tags security

# 5. Fail CI on any error finding
orchestrator scan /path/to/your/repo --fail-on error
```

**Example output:**

```
[ERROR]   [PERM-002] Workflow uses 'write-all' permissions.
          Fix: Use fine-grained permissions instead of 'write-all'.

[WARNING] [SEC-001] Step uses unpinned action: actions/checkout@v4
          Supply-chain risk: tag references can be mutated.
          Fix: Pin to a full commit SHA.

[WARNING] [HARD-001] Step uses actions/checkout without 'persist-credentials: false'.
          The GitHub token is written into the local git config.
          Fix: Add 'with: { persist-credentials: false }' to the checkout step.

Summary: 3 findings (1 error, 2 warnings)
Exit code: 1  (--fail-on error threshold reached)
```

---

## Architecture

Orchestrator is a pure read-only pipeline. No workflow file is ever modified
unless `fix --write` is explicitly passed.

```
YAML Input
.github/workflows/*.yml
        │
        ▼
┌───────────────────┐
│ Parser            │  Orchestrator.Parser
│ YAML → typed AST  │  (Yaml, Aeson)
└────────┬──────────┘
         │
         ▼
┌───────────────────┐
│ Domain Model      │  Orchestrator.Model / Orchestrator.Types
│ Workflow, Job,    │  Strict fields, no partial functions
│ Step, Permissions │
└────────┬──────────┘
         │
    ┌────┴──────────────────────────┐
    │                               │
    ▼                               ▼
┌───────────────────┐   ┌───────────────────────┐
│ Structural        │   │ Policy Engine          │
│ Validation        │   │ Orchestrator.Policy    │
│ Orchestrator.     │   │ Orchestrator.Policy.   │
│ Validate /        │   │   Extended             │
│ Orchestrator.     │   │ Orchestrator.Rules.*   │
│ Graph             │   │ (36 rules, tagged)     │
└────────┬──────────┘   └───────────┬───────────┘
         │                          │
         └──────────┬───────────────┘
                    │
                    ▼
         ┌──────────────────┐
         │ Baseline Filter  │  Orchestrator.Baseline
         │ Suppress         │  Orchestrator.Suppress
         └──────────┬───────┘
                    │
                    ▼
         ┌──────────────────┐
         │ Renderer         │  Orchestrator.Render
         │ Text / JSON      │  Orchestrator.Render.Sarif
         │ SARIF v2.1.0     │  Orchestrator.Render.Markdown
         │ Markdown         │
         └──────────────────┘
```

**Additional analysis modules** (used by specific commands):

| Module | Purpose |
|--------|---------|
| `Orchestrator.Simulate` | Dry-run engine: expands matrix, evaluates if-conditions, traces DAG, estimates duration and cost |
| `Orchestrator.Permissions.Minimum` | Computes minimum required permissions from action catalog; compares against declared permissions |
| `Orchestrator.GitHub` | Remote workflow scanning via GitHub API (owner/repo or org targets) |
| `Orchestrator.Graph` | Job dependency DAG: cycle detection, orphan detection, critical path |
| `Orchestrator.Complexity` | Workflow complexity scoring |
| `Orchestrator.Diff` | Delta between current findings and a saved baseline |
| `Orchestrator.Fix` | Generates fix instructions for mechanical issues |
| `Orchestrator.UI` | Embedded Warp HTTP server for web dashboard (port 8420, LAN/Tailscale only) |

**Language and build:**

- GHC 9.6.7, GHC2021 language edition
- `DerivingStrategies`, `OverloadedStrings`, strict fields on all data types
- `-Wall -Wcompat` + full extended warning set; zero-warning gate in CI
- No partial functions; all file I/O wrapped with `Control.Exception.try`
- Build parallelism capped at 6 cores to prevent thermal issues on constrained runners

---

## Installation

### Binary (Recommended)

Download the pre-built binary from the
[Releases](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/releases) page.

```bash
# Linux x86_64 — tarball
tar xzf haskell-orchestrator-4.0.0-linux-x86_64.tar.gz
sudo cp orchestrator /usr/local/bin/

# Linux x86_64 — Debian/Ubuntu
sudo dpkg -i haskell-orchestrator-4.0.0-amd64.deb

# Linux x86_64 — Fedora/RHEL
sudo rpm -i haskell-orchestrator-4.0.0-x86_64.rpm

# Verify checksum
sha256sum -c SHA256SUMS-4.0.0.txt

# Inspect the SBOM
python3 -m json.tool sbom-4.0.0.json
```

Each release ships a tarball, `.deb`, `.rpm`, Windows zip, SHA-256 checksums, and a
CycloneDX SBOM.

### From Source

```bash
# Prerequisites: GHC 9.6.7, Cabal 3.10+
git clone https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator.git
cd Haskell-Orchestrator
cabal update
cabal build
cabal install exe:orchestrator
```

---

## CI Integration

### Gate on Severity with `--fail-on`

Use `--fail-on` to control when orchestrator exits non-zero. This is the
primary mechanism for blocking PRs on policy violations.

```yaml
# .github/workflows/workflow-lint.yml
name: Workflow Governance

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  orchestrator-scan:
    runs-on: [self-hosted, Linux, X64]
    steps:
      - uses: actions/checkout@3f35a3...  # pin to SHA in production

      - name: Scan workflows — fail on errors
        run: orchestrator scan .github/workflows/ --fail-on error

      - name: Scan workflows — fail on warnings (strict mode)
        run: orchestrator scan .github/workflows/ --fail-on warning
```

`--fail-on` accepts: `info`, `warning`, `error`, `critical`

| Value | Exits non-zero when... |
|-------|----------------------|
| `info` | any finding exists |
| `warning` | any warning, error, or critical finding exists |
| `error` | any error or critical finding exists |
| `critical` | any critical finding exists |

### Selective Scanning with `--tags`

`--tags` is repeatable. Pass it once per tag:

```bash
# Security rules only
orchestrator scan . --tags security

# Security and supply chain rules
orchestrator scan . --tags security --tags supply-chain

# Performance and cost rules
orchestrator scan . --tags performance --tags cost
```

### SARIF Output for GitHub Code Scanning

```bash
orchestrator scan .github/workflows/ --sarif > results.sarif
```

Upload with the `github/codeql-action/upload-sarif` action to surface findings
as GitHub code scanning alerts.

### CI Self-Check (Dogfooding)

This repository scans its own workflows on every push:

```yaml
- name: Run Orchestrator against own workflows
  run: cabal run orchestrator -- scan .github/workflows/ --fail-on error
```

This is the same command you would use in your own CI pipeline.

---

## Rules Reference

v4.0.0 ships **36 rules** across six categories. All rules are tagged and
can be selectively enabled with `--tags`.

Run `orchestrator rules` to list all rules. Run `orchestrator explain RULE_ID`
for detailed guidance on any rule.

### Security (10 rules)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| PERM-001 | Permissions Required | Warning | security |
| PERM-002 | Broad Permissions | Error | security |
| SEC-001 | Unpinned Actions | Warning | security |
| SEC-002 | Secret in Run Step | Error | security |
| SEC-003 | Workflow Run Privilege Escalation | Error | security |
| SEC-004 | Artifact Poisoning | Warning / Error | security |
| SEC-005 | OIDC Token Scope | Warning | security |
| HARD-001 | Missing persist-credentials: false | Warning | security |
| HARD-002 | Default Shell Unset | Warning | security |
| HARD-003 | pull_request_target Risk | Error | security |

Notes:
- **SEC-003** fires when `pull_request_target` is combined with an explicit PR head-ref checkout — a critical write-token attack vector.
- **SEC-004** severity escalates from Warning to Error when the workflow uses a `workflow_run` trigger (artifacts may originate from fork workflows).
- **SEC-005** fires when `id-token: write` is granted but no recognized deployment action (AWS, Azure, GCP, Vault) is present.
- **HARD-001** fires when `actions/checkout` is used without `persist-credentials: false`.
- **HARD-003** fires on `pull_request_target` combined with head-ref checkout.

### Supply Chain (2 rules)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| SUPPLY-001 | Abandoned Action | Warning | security |
| SUPPLY-002 | Typosquat Risk | Info | security |

### Performance (2 rules)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| PERF-001 | Missing Cache for Package Manager | Warning | performance |
| PERF-002 | Sequential Jobs That Could Parallelize | Info | performance |

### Cost (2 rules)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| COST-001 | Matrix Waste | Warning | cost |
| COST-002 | Redundant Artifact Upload/Download | Info | cost |

### Structure (18 rules)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| RUN-001 | Self-Hosted Runner Detection | Info | structure |
| CONC-001 | Missing Concurrency Config | Info | structure |
| RES-001 | Missing Timeout | Warning | structure |
| NAME-001 | Workflow Naming | Info | structure |
| NAME-002 | Job Naming Convention | Info | structure |
| TRIG-001 | Wildcard Triggers | Info | structure |
| GRAPH-001 | Workflow Cycle | Error | structure |
| GRAPH-002 | Orphan Job | Warning | structure |
| DUP-001 | Duplicate Job ID | Error | structure |
| REUSE-001 | Reusable Input Validation | Warning | structure |
| REUSE-002 | Unused Reusable Output | Info | structure |
| MAT-001 | Matrix Explosion | Warning | structure |
| MAT-002 | Matrix Fail-Fast Disabled | Info | structure |
| ENV-001 | Missing Environment URL | Info | structure |
| ENV-002 | Unprotected Approval Gate | Warning | structure |
| COMP-001 | Composite Action Description | Info | structure |
| COMP-002 | Composite Shell Declaration | Warning | structure |
| STRUCT-001 | Circular Workflow Calls | Error | structure |
| STRUCT-002 | Unreferenced Reusable Workflows | Warning | structure |

### Drift (1 rule)

| ID | Name | Severity | Tags |
|----|------|----------|------|
| DRIFT-001 | Action Version Inconsistency Across Workflows | Warning | drift |

---

## Inline Suppression

Suppress a specific rule for a single step or job by adding a comment to your
workflow YAML:

```yaml
steps:
  - name: Deploy
    uses: third-party/action@v2  # orchestrator:disable SEC-001
    with:
      token: ${{ secrets.DEPLOY_TOKEN }}
```

Suppression is scoped to the annotated line. It does not affect other
occurrences of the same rule. The suppression comment is visible in code
review, making it an auditable override rather than a hidden exception.

Disable a rule project-wide in `.orchestrator.yml` instead:

```yaml
policy:
  disabled: [NAME-001, NAME-002]
```

---

## CLI Reference

### Commands

| Command | Description |
|---------|-------------|
| `scan PATH` | Scan workflows and evaluate all configured rules |
| `validate PATH` | Validate workflow structure only (no policy rules) |
| `diff PATH` | Show current issues relative to a saved baseline |
| `plan PATH` | Generate a prioritized remediation plan |
| `fix PATH [--write]` | Produce fix instructions; `--write` applies safe mechanical fixes |
| `baseline PATH` | Save current findings as a baseline for drift detection |
| `demo` | Run a full scan/validate/plan cycle on synthetic fixtures |
| `doctor` | Diagnose environment, configuration, and connectivity |
| `init` | Create a `.orchestrator.yml` with documented defaults |
| `rules` | List all 36 rules with IDs, severity, and tags |
| `explain RULE_ID` | Show full guidance for a specific rule |
| `verify` | Verify the current configuration is valid |
| `upgrade-path PATH` | Show what Business/Enterprise editions would add |
| `ui PATH [--port N]` | Launch the embedded web dashboard (default port 8420) |

### Global Flags

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Configuration file (default: `.orchestrator.yml`) |
| `-v, --verbose` | Enable verbose output |
| `--json` | Output as JSON |
| `--sarif` | Output as SARIF v2.1.0 |
| `--markdown`, `--md` | Output as Markdown |
| `--baseline FILE` | Compare against a saved baseline (show only new findings) |
| `-j, --jobs N` | Number of parallel workers |
| `--fail-on SEVERITY` | Exit non-zero when findings meet or exceed this severity (`info\|warning\|error\|critical`) |
| `--tags TAG` | Filter rules by tag. Repeatable: `--tags security --tags cost` |
| `-w, --watch` | Watch for file changes and re-scan (2s polling interval) |
| `-i, --interactive` | Interactively select rules before scanning |

---

## Configuration

Configuration file: `.orchestrator.yml` (created by `orchestrator init`)

```yaml
scan:
  targets: []             # Explicit scan targets (required for scan command)
  exclude: []             # Paths to exclude from scanning
  max_depth: 10           # Maximum directory recursion depth
  follow_symlinks: false

policy:
  pack: extended          # Policy pack: standard (10 rules) or extended (36 rules)
  min_severity: info      # Minimum severity to report: info, warning, error, critical
  disabled: []            # Rule IDs to disable globally (e.g. [NAME-001, NAME-002])
  tags: []                # Limit to rules with these tags (empty = all rules)

output:
  format: text            # text, json, sarif, or markdown
  verbose: false
  color: true

resources:
  jobs: 4                 # Parallel workers
  profile: safe           # safe, balanced, or fast

gate:
  fail_on: error          # Exit non-zero threshold: info, warning, error, or critical
```

---

## Edition Comparison

Community is free and open source (MIT). Business and Enterprise are
proprietary products for teams with broader needs.

| Feature | Community | Business | Enterprise |
|---------|:---------:|:--------:|:----------:|
| Single-repo scanning | Yes | Yes | Yes |
| 36 policy rules | Yes | Yes | Yes |
| Rule tagging and `--tags` filtering | Yes | Yes | Yes |
| `--fail-on` CI gating | Yes | Yes | Yes |
| Inline suppression | Yes | Yes | Yes |
| JSON / SARIF / Markdown output | Yes | Yes | Yes |
| Demo mode | Yes | Yes | Yes |
| .deb and .rpm packages | Yes | Yes | Yes |
| Multi-repo batch scanning | — | Yes | Yes |
| HTML / CSV reports | — | Yes | Yes |
| Team policy rules | — | Yes | Yes |
| Prioritized remediation with effort estimates | — | Yes | Yes |
| Org-wide governance policies | — | — | Yes |
| Typed enforcement (Advisory/Mandatory/Blocking) | — | — | Yes |
| Immutable audit trail | — | — | Yes |
| SOC 2 / HIPAA compliance mapping | — | — | Yes |
| Compliance artifact generation | — | — | Yes |

**When to upgrade:**

- Multi-repo batch scanning or HTML/CSV reports? Use Business.
- Org-wide governance, audit trails, or compliance frameworks? Use Enterprise.

See [`docs/edition-comparison.md`](docs/edition-comparison.md) for the full
comparison and decision tree.

### Binary Names

All three editions install independently and do not share runtime state:

| Edition | Binary | License |
|---------|--------|---------|
| Community | `orchestrator` | MIT (free) |
| Business | `orchestrator-business` | Private |
| Enterprise | `orchestrator-enterprise` | Private |

---

## Safety Model

Haskell Orchestrator is read-only and self-contained by design:

- **Explicit targets only.** You must specify what to scan. There is no
  automatic filesystem discovery or home-directory crawling.
- **No file modification.** Scan, validate, and plan operations never write
  to disk. Reports and plans are output only. `fix` is dry-run by default;
  pass `--write` to apply changes.
- **No network access during local scans.** Local path scans are pure
  filesystem reads with no network I/O. GitHub API access is only used when
  a `GitHubRepo` or `GitHubOrg` target is explicitly specified.
- **No telemetry.** The binary does not phone home. No background processes.
- **Deterministic output.** The same input and configuration always produce
  the same findings.
- **Bounded parallelism.** Default worker count is conservative. `--jobs`
  gives explicit control. Build parallelism is capped at 6 cores.
- **Dashboard binding.** The `ui` command binds only to local/Tailscale
  interfaces; it never binds to `0.0.0.0`.

See [`docs/safety-model.md`](docs/safety-model.md) for full safety assertions
and evidence.

---

## Development

```bash
# Build
cabal build all

# Run all 599 tests
cabal test all --test-show-details=direct

# Zero-warning gate (matches CI)
cabal clean && cabal build all --ghc-options="-Werror"

# Run demo
cabal run orchestrator -- demo

# Format all source
ormolu --mode inplace $(find src app test -name '*.hs')

# Lint
hlint src/ app/
```

**Test coverage:** 599 tests across unit, property (QuickCheck), integration,
golden, and edge-case suites. Test modules cover every rule, every render
format, simulation, permission analysis, baseline/diff, suppress, gate, hooks,
LSP, and the UI server.

**Code quality:** All source compiles warning-free under `-Wall -Wcompat` plus
ten additional GHC warning flags. All file I/O is wrapped with
`Control.Exception.try`. No partial functions.

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development guidelines.

---

## Documentation

| Document | Description |
|----------|-------------|
| [`docs/architecture.md`](docs/architecture.md) | Module dependency graph and design rationale |
| [`docs/quickstart.md`](docs/quickstart.md) | Step-by-step getting started guide |
| [`docs/operator-guide.md`](docs/operator-guide.md) | Full operator reference |
| [`docs/edition-comparison.md`](docs/edition-comparison.md) | Edition feature matrix and decision tree |
| [`docs/safety-model.md`](docs/safety-model.md) | Safety assertions and evidence |
| [`docs/faq.md`](docs/faq.md) | Frequently asked questions |
| [`docs/output-examples.md`](docs/output-examples.md) | Example output for all formats |
| [`docs/remediation-philosophy.md`](docs/remediation-philosophy.md) | How remediation plans are generated |
| [`docs/deployment-guide.md`](docs/deployment-guide.md) | Deployment and packaging reference |

---

## Release Integrity

Each release includes:

- **SHA-256 checksums** — `SHA256SUMS-4.0.0.txt`
- **CycloneDX SBOM** — `sbom-4.0.0.json`
- **Linux tarball, .deb, and .rpm**
- **Windows binary (zip)**

```bash
sha256sum -c SHA256SUMS-4.0.0.txt
python3 -m json.tool sbom-4.0.0.json
```

---

## Shell Completions

`orchestrator` uses `optparse-applicative`, which provides built-in completion
script generation.

**Bash:**
```bash
orchestrator --bash-completion-script orchestrator \
  > ~/.local/share/bash-completion/completions/orchestrator
```

**Zsh:**
```bash
orchestrator --zsh-completion-script orchestrator \
  > ~/.local/share/zsh/site-functions/_orchestrator
```

**Fish:**
```bash
orchestrator --fish-completion-script orchestrator \
  > ~/.config/fish/completions/orchestrator.fish
```

Pre-generated completion scripts are included in each release archive under
`completions/`.

---

## Sponsor

Haskell Orchestrator is free and open source. If it saves your team time,
please consider sponsoring its development.

**[Become a sponsor on GitHub](https://github.com/sponsors/jalsarraf0)**

---

## License

MIT License. See [LICENSE](LICENSE).
