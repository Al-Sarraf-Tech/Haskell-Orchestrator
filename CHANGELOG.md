# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-04-07

### Added
- 15 new policy rules (36 total): SEC-003 (workflow run privilege escalation), SEC-004 (artifact poisoning), SEC-005 (OIDC token scope), SUPPLY-001 (abandoned action), SUPPLY-002 (typosquat risk), PERF-001 (missing cache), PERF-002 (sequential parallelizable jobs), COST-001 (matrix waste), COST-002 (redundant artifact upload), HARD-001 (missing persist-credentials: false), HARD-002 (default shell unset), HARD-003 (pull request target risk), DRIFT-001 (intra-repo inconsistency), STRUCT-001 (unreferenced reusable workflow), STRUCT-002 (circular workflow call)
- Rule tagging system — all 36 rules tagged by concern (security, performance, cost, style, structure)
- `--tags` flag for selective scanning by tag
- `--fail-on` flag for CI exit code gating (info|warning|error|critical)
- Inline suppression via `# orchestrator:disable RULE-ID` comments in workflow YAML
- Three new FindingCategory values: Performance, Cost, SupplyChain
- Orchestrator self-check CI job (dogfooding)
- .deb and .rpm packaging for Linux releases

### Changed
- Build parallelism capped at 6 cores (was $ncpus) to prevent thermal throttling
- Runtime threading capped at -N6 (was -N, using all cores)
- Test count: 115 → 223

## [3.0.4] - 2026-03-24

### Removed
- Build provenance attestation references (requires public repo or GitHub Enterprise Cloud; not available on Al-Sarraf-Tech org)
- `id-token: write` permission from release workflow (no longer needed)

### Changed
- Release verification documentation updated to reflect checksums + SBOM as the integrity story

## [1.2.1] - 2026-03-16

### Changed
- Version scheme migrated from 4-part (1.1.0.0) to 3-part semver (1.2.1)
- No external dependency changes; community edition remains fully self-contained

## [1.1.0] - 2026-03-15

### Added
- GitHub API integration for remote workflow scanning (Orchestrator.GitHub)
- Auto-remediation module for safe mechanical fixes (Orchestrator.Fix)
- Custom policy rules via .orchestrator.yml configuration
- QuickCheck property-based tests (12 properties)
- Integration tests with realistic workflow patterns (10 tests)
- Parser edge case and fuzz tests (30+ tests)
- Total test count: 115 (was 45)

### Changed
- New dependencies: http-client, http-client-tls, http-types, QuickCheck

## [1.0.5] - 2026-03-15

### Added
- Standalone installation model: each edition installs and runs independently
- Binary install documentation as primary installation method
- Standalone install verification script (`scripts/verify-standalone-install.sh`)
- Standalone install CI workflow (`standalone.yml`)
- Edition independence checks across the product family
- "What Ships with This Edition" documentation in README
- Coexistence guide for running multiple editions on one machine
- Standalone installability assertions in RELEASE_ASSERTIONS

### Changed
- Edition comparison feature matrix corrected for accurate Enterprise column
- Quickstart guide updated to offer binary download as primary option

## [1.0.0] - 2026-03-15

### Added
- GitHub Actions YAML parser with typed domain model
- Policy engine with 10 built-in rules covering permissions, security, naming,
  structure, concurrency, runners, and triggers
- Structural workflow validation (empty jobs, dangling needs, duplicate IDs)
- Diff and remediation plan generation
- CLI with commands: scan, validate, diff, plan, demo, doctor, init, rules,
  explain, verify
- Demo mode with synthetic workflow fixtures (no external access)
- JSON and text output formats
- Configuration file support (.orchestrator.yml)
- Resource control (--jobs N, parallelism profiles: safe/balanced/fast)
- Formal capability contract system with machine-readable manifest
- Tier-boundary validation scripts
- Release verification scripts (6-point pre-release check)
- Cross-platform release artifacts (Linux, macOS, Windows; x86_64 and arm64)
- SHA-256 checksums for all release artifacts
- CycloneDX SBOM generation
- Comprehensive test suite (45 tests)
- 8 documentation guides (quickstart, FAQ, safety model, operator guide, etc.)
- Edition comparison matrix with formal capability IDs
- Sponsor support via GitHub Sponsors

### Security
- Read-only by default: no file modification during scan/validate/plan
- No automatic repository discovery or home-directory crawling
- No telemetry or phone-home behavior
- No self-modifying behavior
- Conservative default resource usage
- Release gate script prevents attribution leaks
