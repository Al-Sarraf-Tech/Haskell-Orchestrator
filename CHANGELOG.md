# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure
- GitHub Actions YAML parser with typed domain model
- Policy engine with 10 built-in rules (permissions, security, naming, structure)
- Structural workflow validation
- Diff and remediation plan generation
- CLI with scan, validate, diff, plan, demo, doctor, init, explain, verify commands
- Demo mode with synthetic workflow fixtures
- JSON and text output formats
- Configuration file support (.orchestrator.yml)
- Resource control (--jobs, parallelism profiles)
- Comprehensive test suite
