# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 3.0.x   | Yes       |
| < 3.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability in Haskell Orchestrator, please
report it responsibly:

1. **Do NOT open a public GitHub issue** for security vulnerabilities.
2. Email security reports to: 19882582+jalsarraf0@users.noreply.github.com
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
4. You will receive an acknowledgment within 72 hours.
5. A fix will be developed and released as quickly as practical.

## Security Design

### Scan Safety

- Orchestrator only accesses paths explicitly provided by the operator.
- No automatic filesystem discovery or home-directory crawling.
- No hidden file traversal outside the specified scan target.
- No network access is performed during local scans.
- No files are modified during scan, validate, or plan operations.

### Supply Chain

- Release binaries include SHA-256 checksums.
- SBOM (Software Bill of Materials) is generated for each release.
- Build provenance attestation is provided via GitHub's artifact attestation.
- No obfuscation or packing is applied to binaries.
- Dependencies are pinned via `cabal.project` index-state.

### Runtime Safety

- No telemetry or phone-home behavior.
- No self-modifying behavior.
- No background services or daemons.
- No persistent state beyond what the operator explicitly configures.
- Conservative default resource usage (bounded parallelism).

### What Is NOT Covered

- This tool does not guarantee the security of scanned workflows.
- Findings are advisory; they do not constitute a security audit.
- The tool does not modify or fix workflows unless explicitly extended to do so.
- Network-based scanning (GitHub API) requires operator-provided credentials.

## Dependency Posture

- Dependencies are updated regularly via Dependabot.
- Major dependency updates are tested in CI before merging.
- The dependency set is intentionally minimal.

## Secure Usage Expectations

- Run the tool in a trusted environment.
- Protect any GitHub tokens used for API-based scanning.
- Review generated remediation plans before applying changes.
- Use `--json` output for programmatic consumption in pipelines.
