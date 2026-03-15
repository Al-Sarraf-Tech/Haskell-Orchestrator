# Haskell Orchestrator

A GitHub Actions workflow standardization, validation, and governance tool
built in Haskell.

Haskell Orchestrator scans GitHub Actions workflows, parses them into a typed
domain model, validates correctness and policy compliance, detects common
issues, and generates deterministic remediation plans.

## Problem Statement

As organizations grow, GitHub Actions workflows drift: permissions become
overly broad, actions go unpinned, timeouts disappear, naming conventions
break down, and security hygiene degrades.  Catching these issues manually
across dozens or hundreds of repositories is impractical.

Haskell Orchestrator automates this by providing a typed, policy-driven
analysis engine that produces clear, actionable findings.

## Design Goals

- **Safe by default** — read-only analysis, no filesystem modification
- **Explicit targets only** — no automatic repo discovery or home-dir crawling
- **Typed correctness** — Haskell's type system enforces model integrity
- **Deterministic output** — same input always produces same findings
- **Policy-driven** — configurable rules with severity levels
- **Operator-friendly** — clear CLI, excellent help text, useful errors
- **Resource-bounded** — conservative defaults, tunable parallelism

## Non-Goals

- Modifying workflow files automatically
- Executing or monitoring CI/CD pipelines
- Managing GitHub repository settings
- Replacing GitHub's built-in security features
- Providing a web dashboard

## Quick Start

### Install from Source

```bash
# Prerequisites: GHC 9.6.x, Cabal 3.10+
git clone https://github.com/jalsarraf0/Haskell-Orchestrator.git
cd Haskell-Orchestrator
cabal update
cabal build
cabal install exe:orchestrator
```

### Try the Demo

```bash
orchestrator demo
```

This runs a complete scan/validate/plan cycle against synthetic workflow
fixtures.  No external repositories are accessed.

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
| `scan PATH...` | Scan workflows in the given paths |
| `validate PATH...` | Validate workflow structure |
| `diff PATH...` | Show current issues |
| `plan PATH...` | Generate a remediation plan |
| `demo` | Run demo with synthetic fixtures |
| `doctor` | Check environment and configuration |
| `init` | Create a new configuration file |
| `explain RULE_ID` | Explain a specific policy rule |
| `verify` | Verify current configuration |

### Global Flags

| Flag | Description |
|------|-------------|
| `-c, --config FILE` | Configuration file (default: `.orchestrator.yml`) |
| `-v, --verbose` | Enable verbose output |
| `--json` | Output results as JSON |
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
sha256sum -c SHA256SUMS-0.1.0.txt

# Verify provenance
gh attestation verify orchestrator-0.1.0-linux-x86_64 --owner jalsarraf0

# Inspect SBOM
python3 -m json.tool sbom-0.1.0.json
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
- macOS and Windows: not tested, may work

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

## Development

```bash
# Build
cabal build all

# Test
cabal test all --test-show-details=direct

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
- **CI** — All tests run on every push and PR

## Release Flow

1. Tag a version: `git tag v0.1.0`
2. Push the tag: `git push origin v0.1.0`
3. GitHub Actions builds, tests, and creates a release with artifacts

## Sponsorship

If you find Haskell Orchestrator useful, consider sponsoring its development.
Sponsorship helps fund ongoing maintenance, new features, and community support.

## License

MIT License. See [LICENSE](LICENSE).
