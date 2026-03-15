# Threat Model — Haskell Orchestrator

## Assets

1. **Scanned workflow files** — The YAML files being analyzed.
2. **Scan findings** — The output of policy evaluation.
3. **GitHub API credentials** — Tokens used for remote scanning (if configured).
4. **Configuration files** — Operator-defined rules and settings.
5. **Remediation plans** — Generated fix recommendations.

## Trust Boundaries

```
┌──────────────────────────────┐
│     Operator Environment     │
│                              │
│  ┌────────────────────────┐  │
│  │   Orchestrator CLI     │  │
│  │  ┌──────────────────┐  │  │
│  │  │ Parser / Policy  │  │  │
│  │  │   Engine         │  │  │
│  │  └──────────────────┘  │  │
│  └──────┬─────────────────┘  │
│         │                    │
│    ┌────▼────┐  ┌─────────┐  │
│    │ Local   │  │ GitHub  │  │
│    │ Files   │  │ API     │  │
│    └─────────┘  └─────────┘  │
└──────────────────────────────┘
```

### Boundary 1: Operator → Tool

The operator provides:
- Explicit scan targets (paths, repos, orgs)
- Configuration
- GitHub credentials (optional)

The tool must not act beyond what the operator explicitly requests.

### Boundary 2: Tool → Local Filesystem

The tool reads workflow files from explicitly specified paths.
It must not traverse beyond the specified scope.

### Boundary 3: Tool → GitHub API

When configured, the tool fetches workflow files via the GitHub API.
Credentials must be handled securely (environment variables, not config files).

## Threat Scenarios

### T1: Path Traversal via Malicious Config

**Threat:** A crafted configuration file causes the tool to read files
outside the intended scan scope.

**Mitigation:** Path validation ensures targets stay within the specified
root. The `max_depth` configuration bounds recursive traversal. Symlink
following is disabled by default.

### T2: Credential Exposure

**Threat:** GitHub tokens are logged, written to disk, or included in output.

**Mitigation:** Credentials are read from environment variables, not config
files. The tool does not log credential values. Output rendering does not
include credential data.

### T3: Malicious Workflow YAML

**Threat:** A crafted YAML file causes excessive resource consumption or
code execution during parsing.

**Mitigation:** The YAML parser (HsYAML/yaml) handles untrusted input.
Parsing is bounded by file size and structure depth. No YAML tags are
executed.  The parser produces a typed domain model, not executable code.

### T4: Supply Chain Attack on Tool Itself

**Threat:** A compromised dependency or build artifact is distributed.

**Mitigation:** Dependencies are pinned. Release artifacts include checksums
and build provenance attestation. SBOM is provided for dependency inspection.
No obfuscation is used.

### T5: Denial of Service via Large Scan

**Threat:** Scanning a very large repository or organization consumes
excessive CPU/memory.

**Mitigation:** Default parallelism is conservative. `--jobs` and
`--parallelism-profile` provide explicit control. Memory usage is bounded
by the number of concurrent workflow files being parsed.

## What Is Mitigated

- Unintended filesystem access (path validation, no auto-discovery)
- Credential leakage (env-var based, not logged)
- Resource exhaustion (bounded parallelism, configurable limits)
- Supply chain compromise (checksums, SBOM, attestation)

## What Is NOT Mitigated

- Bugs in the YAML parsing library itself
- Operator misconfiguration (e.g., scanning sensitive paths intentionally)
- Compromised operator environment
- GitHub API rate limiting or availability
- Correctness of third-party GitHub Actions referenced in workflows
