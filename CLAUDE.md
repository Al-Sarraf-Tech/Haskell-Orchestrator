# CLAUDE.md — Haskell Orchestrator (Community Edition)

## Project Overview

Haskell Orchestrator is a typed analysis engine for GitHub Actions workflows.
It parses workflow YAML into a typed domain model, validates structure,
evaluates configurable policy rules, and generates deterministic remediation
plans — without modifying any files.

- **Edition:** Community (MIT license)
- **Version:** 3.0.3
- **Language:** Haskell (GHC2021)
- **Compiler:** GHC 9.6.7
- **Build tool:** Cabal 3.10+
- **Org:** Al-Sarraf-Tech

## Build / Test / Lint

```bash
cabal build all                              # build library + executable + tests
cabal test all --test-show-details=direct    # run all 115 tests
cabal clean && cabal build all --ghc-options="-Werror"  # zero-warning gate
ormolu --mode inplace $(find src app test -name '*.hs')  # format
```

## Build

```bash
cabal build all
```

## Test

```bash
cabal test all --test-show-details=direct
```

## Lint

```bash
cabal clean && cabal build all --ghc-options="-Werror"
ormolu --mode check $(find src app test -name '*.hs')
```

## Key Directories

```
src/              # Library source (Orchestrator.* modules)
app/              # CLI entry point (Main.hs, CLI.hs)
test/             # Test suite (11 modules: unit, property, integration, golden, edge cases)
demo/             # Synthetic workflow fixtures for demo mode
config/           # Capability contract, configuration templates
docs/             # Operator guide, FAQ, safety model, edition comparison
scripts/          # Install, uninstall, release gate, verification scripts
examples/         # Example .orchestrator.yml configuration
```

## CLI Commands

scan, validate, diff, plan, fix, baseline, demo, doctor, init, rules,
explain, verify, upgrade-path, ui. Run `orchestrator --help` for full reference.

## CI Workflows (.github/workflows/)

- `ci-haskell.yml` — Build, test, lint, capability check (on push/PR to main)
- `release-haskell.yml` — Build Linux + Windows binaries, SBOM, GitHub release (on tag push)
- `security-haskell.yml` — Dependency audit, secret scan, attribution check
- `build-standalone.yml` — Standalone binary verification
- `repo-guard.yml` — Reusable: repository ownership + thermal safety (90°C limit)

All workflows use self-hosted runners: `[self-hosted, Linux, X64, haskell, unified-all]`.

## Release Process

1. Update version in `orchestrator.cabal` and `CHANGELOG.md`
2. `git tag vX.Y.Z && git push origin vX.Y.Z`
3. GitHub Actions builds, tests, packages, and creates a release with binaries + SBOM

Local pre-release checks: `make release-gate` and `make verify`.

## Edition Architecture

Community, Business, and Enterprise are independent repos. Business and
Enterprise inline all Community source code — they are fully self-contained.
No cross-repo build or runtime dependencies.

Tier boundary enforcement: `scripts/check-tier-boundaries.sh` blocks imports
of Business/Enterprise modules in Community source.

## Haskell Conventions

- GHC2021 language edition with DerivingStrategies and OverloadedStrings
- Strict fields on all data types
- Explicit export lists on all modules
- `-Wall -Wcompat` + full warning set (see `common warnings` in .cabal)
- No partial functions
- All file I/O wrapped with `Control.Exception.try`
- QuickCheck property tests with Arbitrary instances for domain types
