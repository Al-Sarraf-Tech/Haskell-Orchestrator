# Haskell Orchestrator

[![Verified by Haskell Orchestrator Enterprise](https://img.shields.io/badge/Verified%20by-Haskell%20Orchestrator%20Enterprise-blueviolet)](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator)
[![CI](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/actions/workflows/ci-haskell.yml/badge.svg)](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/actions/workflows/ci-haskell.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/jalsarraf0)

**Workflow standardization, drift detection, and remediation planning for
GitHub Actions.**

> **Governance Status** — Scanned by [Haskell Orchestrator Enterprise](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator) v3.0.3 on 2026-03-22: **0 findings** across 21 governance rules.

Stop treating CI/CD workflows as one-off configs that nobody reviews.
Haskell Orchestrator discovers workflow sprawl, detects drift from your
standards, validates against configurable policies, and generates clean
remediation plans — all without modifying a single file.

This is **not** a YAML linter. It is a typed analysis engine that understands
the semantics of GitHub Actions workflows: permissions scopes, runner
selection, action pinning, concurrency, trigger patterns, and more.

## Problem Statement

As organizations grow, GitHub Actions workflows drift:
- Permissions become overly broad (`write-all` everywhere)
- Third-party actions go unpinned (supply-chain risk)
- Timeouts disappear (runaway builds burn resources)
- Naming conventions break down
- Security hygiene degrades silently

Manual review across dozens of repos is impractical.  Linters catch syntax
errors but miss semantic issues.  GitHub's built-in tools focus on
vulnerability scanning, not workflow governance.

Haskell Orchestrator fills this gap with a typed, policy-driven analysis
engine that produces clear, actionable, deterministic findings.

## Design Goals

- **Safe by default** — read-only analysis, no filesystem modification
- **Explicit targets only** — no automatic repo discovery or home-dir crawling
- **Typed correctness** — Haskell's type system enforces model integrity
- **Deterministic output** — same input always produces same findings
- **Policy-driven** — configurable rules with severity levels
- **Operator-friendly** — clear CLI, excellent help text, useful errors
- **Resource-bounded** — conservative defaults, tunable parallelism

## Editions

This is the **Community Edition** — free and open source.

| Feature | Community | Business | Enterprise |
|---------|:---------:|:--------:|:----------:|
| Single-repo scanning | Yes | Yes | Yes |
| 10 standard policy rules | Yes | Yes | Yes |
| Structural validation | Yes | Yes | Yes |
| Diff / remediation plans | Yes | Yes | Yes |
| JSON + text output | Yes | Yes | Yes |
| Demo mode | Yes | Yes | Yes |
| Multi-repo batch scanning | — | Yes | Yes |
| HTML / CSV reports | — | Yes | Yes |
| Team policy rules (+4) | — | Yes | Yes |
| Prioritized remediation | — | Yes | Yes |
| Org-wide governance | — | — | Yes |
| Audit trail | — | — | Yes |
| Compliance mapping | — | — | Yes |
| Admin workflows | — | — | Yes |

**When to upgrade:**
- Need multi-repo batch scanning or HTML/CSV reports? → Business
- Need org-wide governance, audit trails, or compliance? → Enterprise

See `docs/edition-comparison.md` for the full comparison.

## Non-Goals

- Modifying workflow files automatically
- Executing or monitoring CI/CD pipelines
- Managing GitHub repository settings
- Replacing GitHub's built-in security features
- Providing a hosted/cloud dashboard service

## Standalone Installation

Community is independently installable. No other edition needs to be
installed. The released binary is self-contained.

### Install from Release Binary (Recommended)

Download the pre-built binary for your platform from the
[Releases](https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator/releases)
page.

```bash
# Linux x86_64
tar xzf haskell-orchestrator-X.Y.Z-linux-x86_64.tar.gz
cd haskell-orchestrator-X.Y.Z-linux-x86_64
sudo cp orchestrator /usr/local/bin/

# Verify
orchestrator demo
```

Each release includes SHA-256 checksums, a CycloneDX SBOM, and build
provenance attestation. See "Release Integrity / Verification" below.

### Install from Source

```bash
# Prerequisites: GHC 9.6.x, Cabal 3.10+
git clone https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator.git
cd Haskell-Orchestrator
cabal update
cabal build
cabal install exe:orchestrator
```

### Verify Installation

```bash
# Quick check
orchestrator demo

# Full standalone verification
bash scripts/verify-standalone-install.sh
```

## What Ships with This Edition

The Community binary includes:

- GitHub Actions YAML parsing into typed domain model
- Single-repository workflow scanning
- 10 standard policy rules (permissions, security, runners, naming, triggers)
- Structural validation (empty jobs, dangling needs, duplicate IDs)
- Diff view and remediation plan generation
- Demo mode with synthetic fixtures (no external access)
- Doctor (environment diagnostics)
- Configuration init and verify
- JSON and text output formats
- Resource-bounded parallelism

### What This Does / Does Not Depend On

- **No runtime dependency on any other edition.** The binary is self-contained.
- No Business or Enterprise installation is required.
- No shared runtime files or config directories with other editions.

## Quick Start

### Try the Demo

```bash
orchestrator demo
```

This runs a complete scan/validate/plan cycle against synthetic workflow
fixtures.  No external repositories are accessed.

<details>
<summary><strong>See demo output</strong> — what <code>orchestrator demo</code> actually produces</summary>

The demo scans 3 synthetic workflows (a clean CI workflow, a problematic deploy,
and an insecure release) to show the full range of findings and remediation plans:

```
Haskell Orchestrator — Demo Mode
════════════════════════════════════════════════════════════

Using synthetic workflow fixtures (no external repos accessed).

Analyzing: CI
  File: demo/.github/workflows/ci.yml

  Structural validation:
    No structural issues.

  Policy findings:
[INFO]     [NAME-001] Workflow has a very short or missing name.
  File: demo/.github/workflows/ci.yml
  Fix: Use a descriptive workflow name (e.g., 'CI', 'Release').

Summary
────────────────────────────────────────
Total findings: 1
  Errors:   0
  Warnings: 0
  Info:     1

By category:
  Naming: 1

────────────────────────────────────────────────────────────

Analyzing: Deploy
  File: demo/.github/workflows/deploy.yml

  Policy findings:
[WARNING]  [PERM-001] Workflow does not declare a top-level permissions block.
  Fix: Add a 'permissions:' block to restrict token scope.

[WARNING]  [SEC-001] Step uses unpinned action: third-party/deploy-action@v2.
           Supply-chain risk: tag references can be mutated.
  Fix: Pin to a full commit SHA instead of a tag.

[WARNING]  [RES-001] Job 'deployProd' has no timeout-minutes.
  Fix: Add 'timeout-minutes:' to bound execution time.

[INFO]     [CONC-001] Workflow has pull_request trigger but no concurrency config.
[INFO]     [NAME-002] Job ID 'deployProd' does not follow kebab-case.
[INFO]     [TRIG-001] Trigger 'push' uses wildcard branch pattern.

Summary: 6 findings (3 warnings, 3 info)

Remediation Plan (3 steps)
────────────────────────────────────────────────────────────
Step 1: PERM-001 — Add a 'permissions:' block to restrict token scope.
Step 2: SEC-001  — Pin to a full commit SHA instead of a tag.
Step 3: RES-001  — Add 'timeout-minutes:' to bound execution time.

────────────────────────────────────────────────────────────

Analyzing: Release
  File: demo/.github/workflows/release.yml

  Policy findings:
[ERROR]    [PERM-002] Workflow uses 'write-all' permissions, granting broad access.
  Fix: Use fine-grained permissions instead of 'write-all'.

[ERROR]    [PERM-002] Job 'release' uses 'write-all' permissions.
  Fix: Use fine-grained permissions instead of 'write-all'.

[ERROR]    [SEC-002] Run step references secrets directly. Secrets in shell
           commands risk exposure in build logs.
  Fix: Pass secrets via environment variables instead.

[WARNING]  [RES-001] Job 'release' has no timeout-minutes.
  Fix: Add 'timeout-minutes:' to bound execution time.

Summary: 4 findings (3 errors, 1 warning)

Remediation Plan (4 steps)
────────────────────────────────────────────────────────────
Step 1: PERM-002 — Use fine-grained permissions instead of 'write-all'.
Step 2: PERM-002 — Use fine-grained permissions instead of 'write-all'.
Step 3: RES-001  — Add 'timeout-minutes:' to bound execution time.
Step 4: SEC-002  — Pass secrets via environment variables instead.

════════════════════════════════════════════════════════════
Demo complete.
```

</details>

### Scan a Local Repository

```bash
orchestrator scan /path/to/your/repo
```

### Initialize Configuration

```bash
orchestrator init
# Creates .orchestrator.yml with documented defaults
```

## Command Reference

| Command | Description |
|---------|-------------|
| `scan PATH` | Scan workflows and evaluate policies |
| `validate PATH` | Validate workflow structure |
| `diff PATH` | Show current issues |
| `plan PATH` | Generate a remediation plan |
| `fix PATH` | Auto-fix safe, mechanical issues (`--write` to apply) |
| `baseline PATH` | Save current findings as baseline for drift detection |
| `demo` | Run demo with synthetic fixtures (no external access) |
| `doctor` | Diagnose environment, config, and connectivity |
| `init` | Create a new .orchestrator.yml config file |
| `rules` | List all available policy rules |
| `explain RULE_ID` | Explain a policy rule in detail |
| `verify` | Verify current configuration |
| `upgrade-path PATH` | Show what Business/Enterprise editions would add |
| `ui PATH [--port N]` | Launch embedded web dashboard (default port 8420) |

### Global Flags

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Configuration file (default: `.orchestrator.yml`) |
| `-v, --verbose` | Enable verbose output |
| `--json` | Output results as JSON |
| `--sarif` | Output results as SARIF |
| `--markdown` | Output results as Markdown |
| `--baseline FILE` | Compare against a saved baseline |
| `-j, --jobs N` | Number of parallel workers |

## Configuration Reference

Configuration file: `.orchestrator.yml`

```yaml
scan:
  targets: []           # Explicit scan targets
  exclude: []           # Paths to exclude
  max_depth: 10         # Maximum directory depth
  follow_symlinks: false

policy:
  pack: standard        # Policy pack name
  min_severity: info    # Minimum severity to report
  disabled: []          # Rule IDs to disable

output:
  format: text          # text or json
  verbose: false
  color: true

resources:
  jobs: 4               # Parallel workers (default: conservative)
  profile: safe         # safe, balanced, or fast
```

## Policy Rules

### Standard Pack

| ID | Name | Severity | Category | Description |
|----|------|----------|----------|-------------|
| PERM-001 | Permissions Required | Warning | Permissions | Workflows should declare explicit permissions |
| PERM-002 | Broad Permissions | Error | Permissions | Detect write-all permission grants |
| RUN-001 | Self-Hosted Runner | Info | Runners | Flag non-standard runners |
| CONC-001 | Missing Concurrency | Info | Concurrency | PR workflows should cancel duplicates |
| SEC-001 | Unpinned Actions | Warning | Security | Third-party actions need SHA pins |
| SEC-002 | Secret in Run Step | Error | Security | Secrets should use env vars |
| RES-001 | Missing Timeout | Warning | Structure | Jobs need timeout-minutes |
| NAME-001 | Workflow Naming | Info | Naming | Names should be descriptive |
| NAME-002 | Job Naming | Info | Naming | Job IDs should be kebab-case |
| TRIG-001 | Wildcard Triggers | Info | Triggers | Avoid wildcard branch patterns |

## Scan Safety Model

Haskell Orchestrator is designed to be safe and predictable:

1. **Explicit targets only.** You must specify what to scan. There is no
   "scan everything" mode. No automatic filesystem discovery.

2. **Read-only by default.** Scan, validate, and plan operations never
   modify files. The tool produces reports and plans, not changes.

3. **No home-directory crawling.** The tool never traverses your home
   directory or any path you didn't explicitly provide.

4. **No hidden file access.** The tool does not read dotfiles, credentials,
   or configuration from outside the scan target.

5. **No network access during local scans.** Local path scans are pure
   filesystem reads with no network I/O.

## Isolation Guarantees

- This project is completely isolated from all other repositories.
- No external repository was scanned, referenced, or used during development.
- All test fixtures and demo data are synthetic and self-contained.
- The tool defaults to isolation: no auto-discovery, no crawling, no hidden coupling.

## Operational Guarantees and Non-Guarantees

### Guarantees

- Deterministic output for the same input and configuration
- Bounded resource usage with configurable limits
- No filesystem modification during analysis
- No network access during local scans
- No telemetry or phone-home behavior
- No background processes or daemons

### Non-Guarantees

- The tool does not guarantee that scanned workflows are secure
- Findings are advisory, not a substitute for security review
- False positives are possible
- The tool does not detect all possible workflow issues
- Build reproducibility is near-reproducible, not bit-for-bit identical

## Safety Assertions

| Assertion | Evidence |
|-----------|----------|
| No filesystem modification | Source code analysis; no write operations in scan/validate/plan paths |
| No auto-discovery | Source code analysis; all scan targets require explicit operator input |
| No telemetry | Source code analysis; no network calls outside explicit GitHub API usage |
| Bounded parallelism | Default worker count is conservative; `--jobs` provides explicit control |
| No obfuscation | Standard GHC compilation; binaries are standard ELF |

## Release Integrity / Verification

Each release includes:
- **SHA-256 checksums** — Verify with `sha256sum -c SHA256SUMS-*.txt`
- **SBOM** — CycloneDX JSON listing all dependencies
- **Build provenance** — GitHub artifact attestation

```bash
# Verify checksum
sha256sum -c SHA256SUMS-3.0.3.txt

# Verify provenance
gh attestation verify haskell-orchestrator-3.0.3-linux-x86_64.tar.gz --owner Al-Sarraf-Tech

# Inspect SBOM
python3 -m json.tool sbom-3.0.3.json
```

## Performance / Resource Model

- Default parallelism: 1 worker (safe profile)
- Balanced profile: CPU count / 2
- Fast profile: CPU count
- Memory: proportional to concurrent workflow count (each is small)
- No background indexing or caching

Override with:
```bash
orchestrator scan --jobs 4 /path/to/repo
```

Or in configuration:
```yaml
resources:
  jobs: 4
  profile: balanced
```

## Compatibility

- GHC 9.6.x
- Cabal 3.10+
- Linux x86_64 (primary)
- Windows x86_64 (binary provided)
- macOS: untested

## Troubleshooting

### Build fails with missing dependencies

```bash
cabal update
cabal build all
```

### "No workflows found"

Ensure the target path contains `.github/workflows/` with `.yml` or `.yaml` files.

### Too many findings

Adjust minimum severity:
```yaml
policy:
  min_severity: warning
```

Or disable specific rules:
```yaml
policy:
  disabled: [NAME-001, NAME-002]
```

## FAQ

**Q: Does this tool modify my workflow files?**
A: No. By default, all operations are read-only. The tool produces reports and plans.

**Q: Do I need to know Haskell to use this?**
A: No. The compiled binary is a standalone CLI tool.

**Q: Can this scan private GitHub repositories?**
A: Yes, with a GitHub token that has appropriate access.

**Q: Is this tool safe to run in CI?**
A: Yes. It is read-only and has no side effects.

## Coexistence with Other Editions

Community, Business, and Enterprise can all be installed on the same machine.
They use distinct binary names and do not share runtime state:

| Edition | Binary | Default Config |
|---|---|---|
| Community | `orchestrator` | `.orchestrator.yml` |
| Business | `orchestrator-business` | `.orchestrator.yml` |
| Enterprise | `orchestrator-enterprise` | `.orchestrator.yml` |

Each binary reads `.orchestrator.yml` independently. They do not interfere
with each other.

## Code Quality

All source code compiles **warning-free** under GHC's strictest practical
warning set. The `common warnings` stanza in `orchestrator.cabal` enables:

```
-Wall -Wcompat -Widentities -Wincomplete-record-updates
-Wincomplete-uni-patterns -Wmissing-export-lists
-Wmissing-home-modules -Wpartial-fields -Wredundant-constraints
```

These flags are shared across the library, executable, and test suite via
`import: warnings`. All file I/O operations are wrapped with
`Control.Exception.try` to handle errors gracefully rather than crashing.

## Development

```bash
# Build (all warnings are errors in CI)
cabal build all

# Test
cabal test all --test-show-details=direct

# Verify zero warnings (CI gate)
cabal clean && cabal build all --ghc-options="-Werror"

# Run demo
cabal run orchestrator -- demo

# Format
ormolu --mode inplace $(find src app test -name '*.hs')
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full development guidelines.

## Testing Strategy

- **Unit tests** — Model, parser, policy, validation, diff, config, rendering
- **Demo fixture tests** — Synthetic workflows produce expected findings
- **Golden tests** — Output stability for key scenarios
- **Property tests** — QuickCheck-driven invariant checking
- **CI** — All tests run on every push and PR (115 tests)

## Release Flow

1. Tag a version: `git tag vX.Y.Z`
2. Push the tag: `git push origin vX.Y.Z`
3. GitHub Actions builds, tests, and creates a release with artifacts

## Sponsor This Project

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/jalsarraf0)

Haskell Orchestrator is free and open source. If it saves your team time or
improves your CI/CD hygiene, please consider sponsoring its development.

Sponsorship directly funds:
- Ongoing maintenance and bug fixes
- New policy rules and detection capabilities
- Documentation improvements
- Community support

**[Become a sponsor on GitHub](https://github.com/sponsors/jalsarraf0)**

## License

MIT License. See [LICENSE](LICENSE).
