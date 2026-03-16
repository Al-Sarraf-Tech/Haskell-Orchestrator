# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- Build provenance attestation via GitHub artifact attestations
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
