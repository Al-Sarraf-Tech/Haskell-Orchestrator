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

> This is not a YAML linter. It understands GitHub Actions semantics:
> permissions scopes, action pinning, job graph cycles, matrix explosion,
> environment gates, concurrency, and more.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [CI Integration](#ci-integration)
- [Rules Reference](#rules-reference)
- [Inline Suppression](#inline-suppression)
- [CLI Reference](#cli-reference)
- [Configuration](#configuration)
- [Edition Comparison](#edition-comparison)
- [Safety Model](#safety-model)
- [Development](#development)
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

[WARNING] [SUPPLY-001] Workflow does not pin all third-party actions to a SHA.
          Fix: Run 'orchestrator fix --tags supply-chain' for a remediation plan.

Summary: 3 findings (1 error, 2 warnings)
Exit code: 1  (--fail-on error threshold reached)
```

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

Each release ships a tarball, `.deb`, `.rpm`, SHA-256 checksums, and a
CycloneDX SBOM.

### From Source

```bash
# Prerequisites: GHC 9.6.x, Cabal 3.10+
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

`--fail-on` accepts: `warning`, `error`, `critical`

| Value | Exits non-zero when... |
|-------|----------------------|
| `warning` | any warning, error, or critical finding exists |
| `error` | any error or critical finding exists |
| `critical` | any critical finding exists |

### Selective Scanning with `--tags`

Run only the rules relevant to a given concern:

```bash
# Security rules only
orchestrator scan . --tags security

# Multiple tag groups
orchestrator scan . --tags security,supply-chain

# Performance and cost rules
orchestrator scan . --tags performance,cost
```

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

### Security

| ID | Name | Severity | Tags |
|----|------|----------|------|
| PERM-001 | Permissions Required | Warning | security |
| PERM-002 | Broad Permissions | Error | security |
| SEC-001 | Unpinned Third-Party Actions | Warning | security, supply-chain |
| SEC-002 | Secret in Run Step | Error | security |
| SEC-003 | Workflow Injection via Expression | Error | security, hardening |
| SEC-004 | Dangerous Permissions Combination | Error | security, hardening |
| SEC-005 | Missing CODEOWNERS for Workflow Dir | Warning | security |
| HARD-001 | Missing `shell` in Run Step | Warning | security, hardening |
| HARD-002 | `continue-on-error: true` in Critical Job | Warning | security, hardening |
| HARD-003 | Privileged Container Without Justification | Error | security, hardening |

### Supply Chain

| ID | Name | Severity | Tags |
|----|------|----------|------|
| SUPPLY-001 | Actions Not Pinned to SHA | Warning | supply-chain, security |
| SUPPLY-002 | First-Party Action Without Version Pin | Info | supply-chain |

### Performance

| ID | Name | Severity | Tags |
|----|------|----------|------|
| PERF-001 | Missing Cache for Package Manager | Warning | performance |
| PERF-002 | Sequential Jobs That Could Parallelize | Info | performance |

### Cost

| ID | Name | Severity | Tags |
|----|------|----------|------|
| COST-001 | Matrix Explosion (Too Many Combinations) | Warning | cost, matrix |
| COST-002 | Redundant Artifact Upload/Download | Info | cost |

### Structure

| ID | Name | Severity | Tags |
|----|------|----------|------|
| RUN-001 | Self-Hosted Runner Detection | Info | structure, runners |
| CONC-001 | Missing Concurrency Config | Info | structure |
| RES-001 | Missing Timeout | Warning | structure |
| NAME-001 | Workflow Naming | Info | structure, naming |
| NAME-002 | Job Naming Convention | Info | structure, naming |
| TRIG-001 | Wildcard Triggers | Info | structure, triggers |
| GRAPH-001 | Workflow Cycle | Error | structure |
| GRAPH-002 | Orphan Job | Warning | structure |
| DUP-001 | Duplicate Job ID | Error | structure |
| REUSE-001 | Reusable Input Validation | Warning | structure |
| REUSE-002 | Unused Reusable Output | Info | structure |
| MAT-001 | Matrix Explosion | Warning | structure, matrix |
| MAT-002 | Matrix Fail-Fast Disabled | Info | structure, matrix |
| ENV-001 | Missing Environment URL | Info | structure |
| ENV-002 | Unprotected Approval Gate | Warning | structure |
| COMP-001 | Composite Action Description | Info | structure |
| COMP-002 | Composite Shell Declaration | Warning | structure |
| STRUCT-001 | Circular Workflow Calls | Error | structure |
| STRUCT-002 | Unreferenced Reusable Workflows | Warning | structure |

### Drift

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
| `diff PATH` | Show current issues relative to baseline |
| `plan PATH` | Generate a prioritized remediation plan |
| `fix PATH` | Produce fix instructions for mechanical issues |
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
| `--sarif` | Output as SARIF |
| `--markdown` | Output as Markdown |
| `--baseline FILE` | Compare against a saved baseline |
| `-j, --jobs N` | Number of parallel workers |
| `--fail-on warning\|error\|critical` | Exit non-zero when findings meet or exceed this severity |
| `--tags TAG[,TAG...]` | Run only rules matching these tags |

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
  fail_on: error          # Exit non-zero threshold: warning, error, or critical
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

### Coexistence

All three editions install independently. They use distinct binary names and
do not share runtime state:

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
  to disk. Reports and plans are output only.
- **No network access during local scans.** Local path scans are pure
  filesystem reads with no network I/O.
- **No telemetry.** The binary does not phone home. No background processes.
- **Deterministic output.** The same input and configuration always produce
  the same findings.
- **Bounded parallelism.** Default worker count is conservative. `--jobs`
  gives explicit control.

See [`docs/safety-model.md`](docs/safety-model.md) for full safety assertions
and evidence.

---

## Development

```bash
# Build
cabal build all

# Run all 223 tests
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

**Test coverage:** 223 tests across unit, property (QuickCheck), integration,
golden, and edge-case suites.

**Code quality:** All source compiles warning-free under GHC's strictest
practical warning set (`-Wall -Wcompat` and ten additional flags). All file
I/O is wrapped with `Control.Exception.try`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development guidelines.

---

## Documentation

| Document | Description |
|----------|-------------|
| [`docs/quickstart.md`](docs/quickstart.md) | Step-by-step getting started guide |
| [`docs/operator-guide.md`](docs/operator-guide.md) | Full operator reference |
| [`docs/edition-comparison.md`](docs/edition-comparison.md) | Edition feature matrix and decision tree |
| [`docs/safety-model.md`](docs/safety-model.md) | Safety assertions and evidence |
| [`docs/faq.md`](docs/faq.md) | Frequently asked questions |
| [`docs/output-examples.md`](docs/output-examples.md) | Example output for all formats |
| [`docs/remediation-philosophy.md`](docs/remediation-philosophy.md) | How remediation plans are generated |

---

## Release Integrity

Each release includes:

- **SHA-256 checksums** — `SHA256SUMS-4.0.0.txt`
- **CycloneDX SBOM** — `sbom-4.0.0.json`
- **Linux tarball, .deb, and .rpm**

```bash
sha256sum -c SHA256SUMS-4.0.0.txt
python3 -m json.tool sbom-4.0.0.json
```

---

## Shell Completions

`orchestrator` uses `optparse-applicative`, which provides built-in completion script generation.

**Bash:**
```bash
orchestrator --bash-completion-script orchestrator > ~/.local/share/bash-completion/completions/orchestrator
```

**Zsh:**
```bash
orchestrator --zsh-completion-script orchestrator > ~/.local/share/zsh/site-functions/_orchestrator
```

**Fish:**
```bash
orchestrator --fish-completion-script orchestrator > ~/.config/fish/completions/orchestrator.fish
```

Pre-generated completion scripts are included in each release archive under `completions/`.

---

## Sponsor

Haskell Orchestrator is free and open source. If it saves your team time,
please consider sponsoring its development.

**[Become a sponsor on GitHub](https://github.com/sponsors/jalsarraf0)**

---

## License

MIT License. See [LICENSE](LICENSE).
