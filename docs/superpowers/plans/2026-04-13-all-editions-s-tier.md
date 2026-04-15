# All Editions S-Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Community, Business, and Enterprise editions to S-tier across all scorecard dimensions within their tier boundaries.

**Architecture:** Three independent repos, each with inlined Community source. Community improvements cascade to Business/Enterprise on next source sync. Work proceeds Community-first (foundations), then Business, then Enterprise. Each phase: tests first (biggest gap), CI hardening second, infrastructure third.

**Tech Stack:** Haskell (GHC2021/GHC 9.6.7), Cabal 3.10+, Tasty (HUnit + QuickCheck), GitHub Actions, Podman/Docker

**Repos:**
- Community: `/home/jalsarraf/git/Haskell-Orchestrator/`
- Business: `/home/jalsarraf/git/Haskell-Orchestrator-Business/`
- Enterprise: `/home/jalsarraf/git/Haskell-Orchestrator-Enterprise/`

---

## Phase 1: Community Edition (B+ → S)

### Current State
- 243 tests, 19/49 modules tested (39%)
- No HPC, no benchmarks, no Containerfile
- HLint non-blocking, ormolu not in CI
- Single GHC version, Dependabot missing Hackage

### Test Pattern Reference

All new test files follow this exact structure:

```haskell
module Test.NewModule (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Data.Text qualified as T
import Orchestrator.Types
import Orchestrator.Model
-- module-specific imports

tests :: TestTree
tests = testGroup "NewModule"
  [ testCase "description" $ do
      let result = function input
      result @?= expected
  ]
```

**Registration:** Add `Test.NewModule` to `orchestrator.cabal` under `other-modules`, import qualified in `test/Main.hs`, add `Test.NewModule.tests` to the test group.

---

### Task 1: Tests for Rules — Composite, Duplicate, Environment, Matrix, Reuse

**Files:**
- Create: `test/Test/CompositeRule.hs`
- Create: `test/Test/DuplicateRule.hs`
- Create: `test/Test/EnvironmentRule.hs`
- Create: `test/Test/MatrixRule.hs`
- Create: `test/Test/ReuseRule.hs`
- Modify: `orchestrator.cabal` (add 5 test modules)
- Modify: `test/Main.hs` (import + wire 5 modules)

Each rule test file tests:
1. Rule fires on a workflow that violates it (positive detection)
2. Rule does NOT fire on a clean workflow (no false positives)
3. Rule metadata (ruleId, severity, category, tags)
4. Edge cases (empty jobs, missing fields)

**Module exports to test:**
- `Orchestrator.Rules.Composite`: `compositeDescriptionRule`, `compositeShellRule`
- `Orchestrator.Rules.Duplicate`: `duplicateJobRule` (DUP-001)
- `Orchestrator.Rules.Environment`: `envApprovalGateRule` (ENV-001), `envMissingUrlRule`
- `Orchestrator.Rules.Matrix`: `matrixExplosionRule` (MAT-001), `matrixFailFastRule`
- `Orchestrator.Rules.Reuse`: `reuseInputValidationRule` (REUSE-001), `reuseUnusedOutputRule`

- [ ] **Step 1:** Create `test/Test/CompositeRule.hs` with tests for `compositeDescriptionRule` and `compositeShellRule`. Test that workflows with missing step descriptions and unsafe shell usage produce findings, and clean workflows produce none. Verify ruleId, severity, tags on each finding.

- [ ] **Step 2:** Create `test/Test/DuplicateRule.hs` testing `duplicateJobRule`. Build workflow with duplicate job steps (same uses + same with params), verify finding. Build workflow with unique steps, verify no finding. Test edge: single-step job, empty workflow.

- [ ] **Step 3:** Create `test/Test/EnvironmentRule.hs` testing `envApprovalGateRule` and `envMissingUrlRule`. Build workflow with environment requiring approval but no protection, verify finding. Build workflow with environment URL missing, verify finding. Clean cases for both.

- [ ] **Step 4:** Create `test/Test/MatrixRule.hs` testing `matrixExplosionRule` and `matrixFailFastRule`. Build workflow with matrix > threshold dimensions, verify explosion warning. Build workflow with matrix missing fail-fast, verify finding. Small matrix and fail-fast: true = clean.

- [ ] **Step 5:** Create `test/Test/ReuseRule.hs` testing `reuseInputValidationRule` and `reuseUnusedOutputRule`. Build reusable workflow with unvalidated inputs, verify finding. Build workflow with unused outputs, verify finding. Clean cases.

- [ ] **Step 6:** Run `cabal test all --test-show-details=direct`, verify all new tests pass.

- [ ] **Step 7:** Commit: "test: add unit tests for 5 extended rule modules (Composite, Duplicate, Environment, Matrix, Reuse)"

---

### Task 2: Tests for Rendering — Markdown, SARIF, Upgrade

**Files:**
- Create: `test/Test/RenderMarkdown.hs`
- Create: `test/Test/RenderSarif.hs`
- Create: `test/Test/RenderUpgrade.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Render.Markdown`: `renderMarkdownFindings`, `renderMarkdownSummary`, `renderMarkdownPlan`
- `Orchestrator.Render.Sarif`: `renderSarif`, `renderSarifJSON`, `sarifVersion`
- `Orchestrator.Render.Upgrade`: `renderUpgradePath`, `estimateUpgradeImpact`

- [ ] **Step 1:** Create `test/Test/RenderMarkdown.hs`. Test `renderMarkdownFindings` with 0, 1, 3 findings — verify output contains markdown table headers, pipe characters, finding text. Test `renderMarkdownSummary` produces summary line. Test `renderMarkdownPlan` with a remediation plan.

- [ ] **Step 2:** Create `test/Test/RenderSarif.hs`. Test `sarifVersion` equals "2.1.0". Test `renderSarif` with empty findings produces valid JSON structure with `$schema`, `version`, `runs` array. Test with findings that SARIF `results` array has correct `ruleId`, `level`, `message`. Test `renderSarifJSON` produces parseable JSON text.

- [ ] **Step 3:** Create `test/Test/RenderUpgrade.hs`. Test `estimateUpgradeImpact` returns two UpgradeInfo (Business, Enterprise). Test UpgradeInfo fields: edition name, additionalRules > 0, newCapabilities non-empty. Test `renderUpgradePath` produces text output mentioning both editions.

- [ ] **Step 4:** Run tests, verify pass. Commit: "test: add rendering format tests (Markdown, SARIF, Upgrade)"

---

### Task 3: Tests for Actions — Catalog, Pin

**Files:**
- Create: `test/Test/ActionsCatalog.hs`
- Create: `test/Test/ActionsPin.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Actions.Catalog`: `catalogActions`, `checkActionHealth`, `actionHealthRule`, `deprecatedActions`
- `Orchestrator.Actions.Pin`: `analyzePinning`, `PinStatus(..)`, `PinAction(..)`

- [ ] **Step 1:** Create `test/Test/ActionsCatalog.hs`. Test `catalogActions` on workflow with known actions returns ActionInfo list. Test `checkActionHealth` flags deprecated actions. Test `actionHealthRule` as PolicyRule — verify ruleId, fires on deprecated action usage. Test `deprecatedActions` is non-empty.

- [ ] **Step 2:** Create `test/Test/ActionsPin.hs`. Test `analyzePinning` on workflow with `uses: actions/checkout@v4` returns PinAction with `CanPin` status. Test SHA-pinned action returns `AlreadyPinned`. Test `uses: ./local-action` returns `LocalAction`. Test `uses: docker://image` returns `DockerAction`. Empty workflow returns empty list.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add action catalog and pinning analysis tests"

---

### Task 4: Tests for Simulation — Simulate, Conditions, Matrix, Types

**Files:**
- Create: `test/Test/Simulate.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Simulate`: `simulateWorkflow`
- `Orchestrator.Simulate.Conditions`: `evaluateCondition`
- `Orchestrator.Simulate.Matrix`: `expandMatrix`, `estimateMatrixSize`, `extractDimensions`
- `Orchestrator.Simulate.Types`: `defaultContext`, `isRunning`, `isSkipped`

- [ ] **Step 1:** Create `test/Test/Simulate.hs` with 4 subgroups. Test `defaultContext` fields are sensible defaults. Test `isRunning`/`isSkipped` status predicates. Test `evaluateCondition` with "always()" returns running, with "github.ref == 'refs/heads/main'" and matching context returns running, non-matching returns skipped. Test `expandMatrix` on job with 2x2 matrix returns 4 combinations. Test `estimateMatrixSize` returns product of dimensions. Test `simulateWorkflow` on demo goodWorkflow produces SimulationResult with jobs matching workflow job count.

- [ ] **Step 2:** Run tests, verify pass. Commit: "test: add workflow simulation engine tests"

---

### Task 5: Tests for Analysis — Graph, Complexity, Baseline, Changelog

**Files:**
- Create: `test/Test/Graph.hs`
- Create: `test/Test/Complexity.hs`
- Create: `test/Test/Baseline.hs`
- Create: `test/Test/Changelog.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Graph`: `buildJobGraph`, `detectCycles`, `findOrphanedJobs`, `topologicalSort`, `graphCycleRule`, `graphOrphanRule`
- `Orchestrator.Complexity`: `computeComplexity`, `complexityRule`
- `Orchestrator.Baseline`: `saveBaseline`, `loadBaseline`, `compareWithBaseline`
- `Orchestrator.Changelog`: `diffWorkflows`, `ChangeType(..)`

- [ ] **Step 1:** Create `test/Test/Graph.hs`. Test `buildJobGraph` on workflow with needs dependencies produces edges. Test `detectCycles` on DAG returns empty, on cyclic graph returns cycle. Test `findOrphanedJobs` on workflow with unreferenced job returns it. Test `topologicalSort` on simple DAG returns valid ordering. Test `graphCycleRule` and `graphOrphanRule` as PolicyRules — verify they fire on problematic workflows.

- [ ] **Step 2:** Create `test/Test/Complexity.hs`. Test `computeComplexity` on minimal workflow returns low score. Test on workflow with deep nesting, large matrix, many steps returns higher score. Test `complexityRule` fires when score exceeds threshold. Test each ComplexityDimension contributes to total.

- [ ] **Step 3:** Create `test/Test/Baseline.hs`. Test `saveBaseline`/`loadBaseline` roundtrip in temp directory (use System.IO.Temp). Test `compareWithBaseline` detects new findings not in baseline. Test baseline with identical findings returns no new. Test loading non-existent baseline returns empty/error gracefully.

- [ ] **Step 4:** Create `test/Test/Changelog.hs`. Test `diffWorkflows` on identical workflows returns empty. Test adding a job returns Added entry. Test removing a step returns Removed entry. Test modifying a field returns Modified entry.

- [ ] **Step 5:** Run tests, verify pass. Commit: "test: add graph, complexity, baseline, and changelog analysis tests"

---

### Task 6: Tests for Fix and Formatter

**Files:**
- Create: `test/Test/Fix.hs`
- Create: `test/Test/Formatter.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Fix`: `analyzeFixable`, `FixAction(..)`, `defaultFixConfig`
- `Orchestrator.Formatter`: `formatWorkflowYAML`, `defaultFormatConfig`, `QuoteStyle(..)`

- [ ] **Step 1:** Create `test/Test/Fix.hs`. Test `analyzeFixable` on workflow with SEC-001 finding returns FixAction with patch text. Test `defaultFixConfig` has sensible defaults. Test on clean workflow returns empty FixAction list. Test FixAction fields: faRuleId matches the finding's rule.

- [ ] **Step 2:** Create `test/Test/Formatter.hs`. Test `formatWorkflowYAML` with `defaultFormatConfig` on valid YAML returns normalized output. Test `SingleQuote` vs `DoubleQuote` style. Test `fcSortKeys = True` sorts YAML keys. Test malformed YAML returns error gracefully.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add fix engine and YAML formatter tests"

---

### Task 7: Tests for Scan, GitHub, Hook, LSP

**Files:**
- Create: `test/Test/Scan.hs`
- Create: `test/Test/GitHub.hs`
- Create: `test/Test/Hook.hs`
- Create: `test/Test/LSP.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Scan`: `findWorkflowFiles`, `isWorkflowFile`
- `Orchestrator.GitHub`: `defaultGitHubConfig`
- `Orchestrator.Hook`: `hookScript`, `defaultHookConfig`
- `Orchestrator.LSP`: `findingsToDiagnostics`, `DiagSeverity(..)`

- [ ] **Step 1:** Create `test/Test/Scan.hs`. Test `isWorkflowFile` returns True for `.github/workflows/ci.yml`, False for `src/main.hs`. Test `findWorkflowFiles` on the repo's own `demo/` directory finds `.yml` files. Test `scanLocalPath` on demo directory returns Right ScanResult.

- [ ] **Step 2:** Create `test/Test/GitHub.hs`. Test `defaultGitHubConfig` fields are sensible. (Skip network tests — pure function testing only, no HTTP calls in unit tests.)

- [ ] **Step 3:** Create `test/Test/Hook.hs`. Test `hookScript` returns non-empty script text containing "orchestrator". Test `defaultHookConfig` fields. Test `runHookCheck` concept — pure validation on findings list.

- [ ] **Step 4:** Create `test/Test/LSP.hs`. Test `findingsToDiagnostics` maps Finding severity to DiagSeverity correctly (Error→DiagError, Warning→DiagWarning, etc.). Test empty findings produces empty diagnostics. Test diagnostic range fields are populated.

- [ ] **Step 5:** Run tests, verify pass. Commit: "test: add scan, GitHub config, hook, and LSP diagnostic tests"

---

### Task 8: Tests for Secrets, Permissions.Minimum

**Files:**
- Create: `test/Test/Secrets.hs`
- Create: `test/Test/PermissionsMinimum.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.Secrets`: `analyzeSecrets`, `buildSecretScopes`, `secretScopeRule`
- `Orchestrator.Permissions.Minimum`: `analyzePermissions`, `permissionsMinimumRule`, `actionPermissionCatalog`

- [ ] **Step 1:** Create `test/Test/Secrets.hs`. Test `analyzeSecrets` on workflow using `${{ secrets.GITHUB_TOKEN }}` returns SecretRef. Test `buildSecretScopes` groups refs by secret name. Test `secretScopeRule` fires on overly broad secret usage. Test workflow with no secrets returns empty list.

- [ ] **Step 2:** Create `test/Test/PermissionsMinimum.hs`. Test `actionPermissionCatalog` is non-empty map. Test `analyzePermissions` on workflow with `permissions: write-all` and actions/checkout detects excess permissions. Test `permissionsMinimumRule` fires on over-permissioned workflow. Test workflow with minimal permissions produces no excess.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add secret analysis and minimum permissions tests"

---

### Task 9: Tests for UI and Version

**Files:**
- Create: `test/Test/UI.hs`
- Create: `test/Test/Version.hs`
- Modify: `orchestrator.cabal`, `test/Main.hs`

**Module exports to test:**
- `Orchestrator.UI`: `renderDashboardHTML`, `renderAPIJSON`, `DashboardData(..)`
- `Orchestrator.UI.Server`: `parseBindAddrs`, `defaultServerConfig`
- `Orchestrator.Version`: `orchestratorVersion`, `orchestratorEdition`, `userAgentString`

- [ ] **Step 1:** Create `test/Test/UI.hs`. Test `renderDashboardHTML` with DashboardData containing findings returns HTML with `<html>`, `<body>`, finding count. Test `renderAPIJSON` returns parseable JSON. Test `parseBindAddrs` parses "0.0.0.0:8080" correctly. Test `defaultServerConfig` has sensible port.

- [ ] **Step 2:** Create `test/Test/Version.hs`. Test `orchestratorVersion` matches cabal version "4.0.0". Test `orchestratorEdition` equals "Community". Test `userAgentString` contains both version and edition.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add UI rendering, server config, and version constant tests"

---

### Task 10: Wire all new test modules and verify full suite

**Files:**
- Modify: `orchestrator.cabal` (add all 19 new test modules to other-modules)
- Modify: `test/Main.hs` (import + wire all 19 modules)

- [ ] **Step 1:** Add all new test modules to `orchestrator.cabal` `other-modules` section alphabetically: Test.ActionsCatalog, Test.ActionsPin, Test.Baseline, Test.Changelog, Test.Complexity, Test.CompositeRule, Test.DuplicateRule, Test.EnvironmentRule, Test.Fix, Test.Formatter, Test.GitHub, Test.Graph, Test.Hook, Test.LSP, Test.MatrixRule, Test.PermissionsMinimum, Test.RenderMarkdown, Test.RenderSarif, Test.RenderUpgrade, Test.ReuseRule, Test.Scan, Test.Secrets, Test.Simulate, Test.UI, Test.Version

- [ ] **Step 2:** Import all qualified in `test/Main.hs` and add `.tests` to the testGroup list.

- [ ] **Step 3:** Run `cabal clean && cabal build all --ghc-options="-Werror"` — verify zero warnings.

- [ ] **Step 4:** Run `cabal test all --test-show-details=direct` — verify all tests pass (target: 400+ tests).

- [ ] **Step 5:** Commit: "test: wire 25 new test modules into test suite (400+ tests)"

---

### Task 11: CI Hardening — ormolu enforcement, HLint blocking, HPC coverage

**Files:**
- Modify: `.github/workflows/ci-haskell.yml`
- Create: `.hlint.yaml`

- [ ] **Step 1:** Add ormolu format check step to ci-haskell.yml build-and-test job, BEFORE the build step:

```yaml
- name: Check formatting (ormolu)
  run: |
    ormolu --mode check $(find src app test -name '*.hs')
```

- [ ] **Step 2:** Change HLint step from `--no-exit-code` to blocking (remove `--no-exit-code`). Add `.hlint.yaml` with:

```yaml
# HLint configuration
- ignore: {name: "Use newtype instead of data"}
- ignore: {name: "Reduce duplication", within: [Test]}
```

- [ ] **Step 3:** Add HPC coverage step after test step:

```yaml
- name: Test with coverage
  run: |
    cabal test all --enable-coverage --test-show-details=direct
    find dist-newstyle -name "*.html" -path "*hpc*" | head -5
```

- [ ] **Step 4:** Add Haddock generation step:

```yaml
- name: Generate Haddock docs
  run: cabal haddock all --haddock-html
```

- [ ] **Step 5:** Run `ormolu --mode check $(find src app test -name '*.hs')` locally, fix any formatting issues, commit.

- [ ] **Step 6:** Commit: "ci: enforce ormolu formatting, make HLint blocking, add HPC coverage and Haddock generation"

---

### Task 12: Containerfile and container build

**Files:**
- Create: `Containerfile`
- Create: `.dockerignore`
- Modify: `.github/workflows/ci-haskell.yml` (add container build step)

- [ ] **Step 1:** Create `.dockerignore`:

```
dist-newstyle/
.git/
.github/
docs/
demo/
test/
*.md
```

- [ ] **Step 2:** Create `Containerfile` (multi-stage, Podman-compatible):

```dockerfile
# Build stage
FROM docker.io/library/haskell:9.6.7-slim AS build
WORKDIR /build
COPY orchestrator.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies
COPY . .
RUN cabal build exe:orchestrator -O2 \
    && cp $(cabal list-bin orchestrator) /usr/local/bin/orchestrator \
    && strip /usr/local/bin/orchestrator

# Runtime stage
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -r -s /bin/false orchestrator
COPY --from=build /usr/local/bin/orchestrator /usr/local/bin/orchestrator
USER orchestrator
ENTRYPOINT ["orchestrator"]
CMD ["--help"]
```

- [ ] **Step 3:** Test locally: `podman build -f Containerfile -t orchestrator:test . && podman run --rm orchestrator:test --help`

- [ ] **Step 4:** Add container build verification step to CI (build only, no push):

```yaml
- name: Verify container build
  run: |
    podman build -f Containerfile -t orchestrator:ci-${{ github.sha }} .
    podman run --rm orchestrator:ci-${{ github.sha }} --help
```

- [ ] **Step 5:** Commit: "feat: add Containerfile with multi-stage build and CI verification"

---

### Task 13: Benchmark suite

**Files:**
- Create: `bench/Main.hs`
- Modify: `orchestrator.cabal` (add benchmark stanza)
- Modify: `Makefile` (add bench target)

- [ ] **Step 1:** Add benchmark stanza to `orchestrator.cabal`:

```cabal
benchmark orchestrator-bench
  type:             exitcode-stdio-1.0
  hs-source-dirs:   bench
  main-is:          Main.hs
  default-language:  GHC2021
  ghc-options:       -O2 -threaded -rtsopts
  build-depends:
    , base             >=4.18  && <4.20
    , orchestrator
    , tasty-bench      >=0.3   && <0.5
    , bytestring
    , text
```

- [ ] **Step 2:** Create `bench/Main.hs`:

```haskell
module Main (main) where

import Test.Tasty.Bench (bench, bgroup, defaultMain, nf, env)
import Data.ByteString.Char8 qualified as BS
import Orchestrator.Parser (parseWorkflowBS)
import Orchestrator.Policy (evaluatePolicies, defaultPolicyPack)
import Orchestrator.Policy.Extended (extendedPolicyPack)
import Orchestrator.Demo (goodWorkflow, problematicWorkflow)
import Orchestrator.Validate (validateWorkflow)
import Orchestrator.Diff (generatePlan)
import Orchestrator.Graph (buildJobGraph, analyzeGraph)

main :: IO ()
main = defaultMain
  [ bgroup "parse"
      [ bench "small workflow" $ nf (parseWorkflowBS "bench.yml") smallYAML
      , bench "large workflow" $ nf (parseWorkflowBS "bench.yml") largeYAML
      ]
  , bgroup "policy"
      [ bench "standard pack / good" $ nf (evaluatePolicies defaultPolicyPack) goodWorkflow
      , bench "extended pack / problematic" $ nf (evaluatePolicies extendedPolicyPack) problematicWorkflow
      ]
  , bgroup "validate"
      [ bench "good workflow" $ nf validateWorkflow goodWorkflow
      , bench "problematic workflow" $ nf validateWorkflow problematicWorkflow
      ]
  , bgroup "graph"
      [ bench "build graph" $ nf buildJobGraph goodWorkflow
      ]
  , bgroup "plan"
      [ bench "generate plan" $ nf generatePlan findings
      ]
  ]
  where
    smallYAML = BS.pack $ unlines
      ["name: CI", "on: push", "jobs:", "  build:", "    runs-on: ubuntu-latest"
      , "    steps:", "      - uses: actions/checkout@v4"]
    largeYAML = BS.pack $ unlines $ concat
      [ ["name: Large", "on: push", "jobs:"]
      , concatMap (\i -> ["  job" ++ show i ++ ":", "    runs-on: ubuntu-latest"
        , "    steps:", "      - uses: actions/checkout@v4"
        , "      - run: echo step " ++ show i]) [1..20 :: Int]
      ]
    findings = evaluatePolicies extendedPolicyPack problematicWorkflow
```

- [ ] **Step 3:** Add Makefile target:

```makefile
bench:
	cabal bench all
```

- [ ] **Step 4:** Run `cabal bench all`, verify benchmarks execute. Commit: "feat: add tasty-bench benchmark suite with parse/policy/validate/graph benchmarks"

---

### Task 14: Makefile expansion and Dependabot fix

**Files:**
- Modify: `Makefile` (add coverage, haddock, container targets)
- Modify: `.github/dependabot.yml` (add Hackage ecosystem)

- [ ] **Step 1:** Add targets to Makefile:

```makefile
coverage:
	cabal test all --enable-coverage --test-show-details=direct

haddock:
	cabal haddock all --haddock-html

container:
	podman build -f Containerfile -t orchestrator:local .

ci-local: format lint test coverage haddock container
	@echo "All local CI checks passed."
```

- [ ] **Step 2:** Update `.github/dependabot.yml` — add Hackage ecosystem:

```yaml
  - package-ecosystem: "cabal"
    directory: "/"
    schedule:
      interval: "weekly"
```

- [ ] **Step 3:** Commit: "chore: expand Makefile targets (coverage, haddock, container, ci-local) and add Dependabot for Hackage"

---

### Task 15: Property tests expansion

**Files:**
- Modify: `test/Test/Properties.hs`

- [ ] **Step 1:** Add property tests for newly-tested modules:
  - Graph: `prop_topologicalSortPreservesAllJobs` — sort result has same elements as input
  - Simulate: `prop_defaultContextFieldsNonEmpty` — all defaultContext fields are non-empty
  - Complexity: `prop_complexityNonNegative` — complexity score >= 0 for any workflow
  - Baseline: `prop_baselineRoundtrip` — save then load returns same fingerprints
  - Pin: `prop_analyzePinningCoversAllActions` — result length matches action count in workflow

- [ ] **Step 2:** Run tests, verify pass. Commit: "test: expand property test suite with graph, simulation, complexity, baseline, pinning properties"

---

## Phase 2: Business Edition (A- → S)

### Current State
- 59 tests, 6/14 Business modules tested (43%)
- 8 untested modules (989 LoC)
- Version 3.0.3 (behind Community 4.0.0)
- No Containerfile, no HPC, no benchmarks

**Working directory:** `/home/jalsarraf/git/Haskell-Orchestrator-Business/`

---

### Task 16: Tests for DiffAware and PRComment

**Files:**
- Create: `test/Test/DiffAware.hs`
- Create: `test/Test/PRComment.hs`
- Modify: `orchestrator-business.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/DiffAware.hs`. Test `getChangedWorkflows` with mocked git output (test pure logic, not git subprocess). Test `scanChangedOnly` filters to only changed files. Test empty diff returns empty list.

- [ ] **Step 2:** Create `test/Test/PRComment.hs`. Test `formatPRComment` with findings produces markdown with emoji. Test severity grouping (errors first, warnings next, info collapsible). Test `formatPRReviewBody` produces structured review. Test empty findings produces "all clear" message. Test special characters in finding text are escaped.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add DiffAware and PRComment integration tests"

---

### Task 17: Tests for Trend and Similarity

**Files:**
- Create: `test/Test/Trend.hs`
- Create: `test/Test/Similarity.hs`
- Modify: `orchestrator-business.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/Trend.hs`. Test TrendEntry JSON serialization roundtrip. Test TrendSummary direction: decreasing finding count = "improving", increasing = "degrading", stable = "stable". Test JSONL format: multiple entries separated by newlines, each parseable.

- [ ] **Step 2:** Create `test/Test/Similarity.hs`. Test similarity detection on two identical findings returns high score. Test completely different findings return low score. Test deduplication groups similar findings.

- [ ] **Step 3:** Run tests, verify pass. Commit: "test: add trend tracking and similarity detection tests"

---

### Task 18: Tests for AdoptionTracker, CIHealth, CostAttribution, Migration

**Files:**
- Create: `test/Test/AdoptionTracker.hs`
- Create: `test/Test/CIHealth.hs`
- Create: `test/Test/CostAttribution.hs`
- Create: `test/Test/Migration.hs`
- Modify: `orchestrator-business.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/AdoptionTracker.hs`. Test adoption metric calculation on scan results. Test team-level aggregation. Test empty input produces zero metrics.

- [ ] **Step 2:** Create `test/Test/CIHealth.hs`. Test CI health scoring on workflow with best practices. Test scoring on workflow with issues produces lower score. Test health report rendering.

- [ ] **Step 3:** Create `test/Test/CostAttribution.hs`. Test cost attribution with matrix workflows. Test runner-type cost estimates. Test aggregation by team/repo.

- [ ] **Step 4:** Create `test/Test/Migration.hs`. Test migration path detection. Test migration step generation. Test empty/already-migrated cases.

- [ ] **Step 5:** Wire all 6 new test modules into cabal + Main.hs. Run full suite. Commit: "test: add adoption, CI health, cost attribution, and migration tests"

---

### Task 19: Business CI hardening + Containerfile

**Files:**
- Modify: `.github/workflows/ci-haskell.yml` (ormolu, HLint blocking, HPC, Haddock)
- Create: `Containerfile`
- Create: `.dockerignore`
- Create: `.hlint.yaml`
- Modify: `Makefile` (add coverage, haddock, bench, container targets)

- [ ] **Step 1:** Mirror Community CI hardening pattern from Task 11: add ormolu check, make HLint blocking, add HPC coverage step, add Haddock generation step.

- [ ] **Step 2:** Create Containerfile (same multi-stage pattern as Community, binary name `orchestrator-business`).

- [ ] **Step 3:** Create `.hlint.yaml` and `.dockerignore` (same as Community).

- [ ] **Step 4:** Expand Makefile with coverage, haddock, container, bench targets.

- [ ] **Step 5:** Fix format: run `ormolu --mode inplace $(find src app test -name '*.hs')`, verify clean.

- [ ] **Step 6:** Run full CI checks locally. Commit: "ci: harden CI (ormolu, HLint blocking, HPC, Haddock), add Containerfile"

---

### Task 20: Business version sync

**Files:**
- Check: `orchestrator-business.cabal` version field
- Check: `CHANGELOG.md`
- Check: `CLAUDE.md`

- [ ] **Step 1:** Verify version consistency across all files. If cabal says 3.0.3 and Community is 4.0.0, this is expected (independent versioning) — document but don't change unless user wants sync.

- [ ] **Step 2:** Verify CLAUDE.md version matches cabal. Fix if mismatched.

- [ ] **Step 3:** Commit if changes needed: "docs: sync version references"

---

## Phase 3: Enterprise Edition (A → S)

### Current State
- 175 tests total, but 9 of 15 test files NOT wired into Main.hs
- 14/18 Enterprise modules untested (2,082 LoC)
- Version mismatch: cabal 4.0.0, CLAUDE.md 3.0.3, docker-compose 3.0.0
- Missing script: fetch-dependencies.sh
- Has Dockerfile (good) but stale version

**Working directory:** `/home/jalsarraf/git/Haskell-Orchestrator-Enterprise/`

---

### Task 21: Fix test Main.hs wiring (9 missing test files)

**Files:**
- Modify: `test/Main.hs`

- [ ] **Step 1:** Read current `test/Main.hs` to see which 6 modules are imported. Read `orchestrator-enterprise.cabal` to see all 15 listed test modules.

- [ ] **Step 2:** Add the 9 missing test module imports to Main.hs and wire into testGroup. This alone adds ~100 previously-invisible tests to the suite.

- [ ] **Step 3:** Run `cabal test all --test-show-details=direct`, verify all 15 test files execute.

- [ ] **Step 4:** Commit: "fix: wire all 15 test modules into test Main.hs (9 were missing)"

---

### Task 22: Tests for RBAC, RiskScore, PolicyInheritance, DriftDetection

**Files:**
- Create: `test/Test/RBAC.hs`
- Create: `test/Test/RiskScore.hs`
- Create: `test/Test/PolicyInheritance.hs`
- Create: `test/Test/DriftDetection.hs`
- Modify: `orchestrator-enterprise.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/RBAC.hs`. Test each role (PolicyAdmin, Auditor, Operator, Viewer) has correct permission set. Test PolicyAdmin can enforce, Viewer cannot. Test authorization check function.

- [ ] **Step 2:** Create `test/Test/RiskScore.hs`. Test risk score calculation: workflow with 0 findings = low risk, many critical findings = high risk. Test score is clamped 0-100. Test per-repo heatmap generation.

- [ ] **Step 3:** Create `test/Test/PolicyInheritance.hs`. Test org-level policy applies to all repos. Test team-level override takes precedence over org. Test repo-level override takes precedence over team. Test cascade resolution.

- [ ] **Step 4:** Create `test/Test/DriftDetection.hs`. Test drift detected when current findings exceed baseline. Test no drift when findings match or improve. Test regression alert generation.

- [ ] **Step 5:** Wire modules, run tests. Commit: "test: add RBAC, risk scoring, policy inheritance, and drift detection tests"

---

### Task 23: Tests for EvidenceVault, EvidenceChain, Attestation

**Files:**
- Create: `test/Test/EvidenceVault.hs`
- Create: `test/Test/EvidenceChain.hs`
- Create: `test/Test/Attestation.hs`
- Modify: `orchestrator-enterprise.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/EvidenceVault.hs`. Test evidence bundle creation from compliance data. Test tamper-evident property: modifying bundle invalidates it. Test storage and retrieval roundtrip. Test access control (Auditor can read, Viewer cannot).

- [ ] **Step 2:** Create `test/Test/EvidenceChain.hs`. Test chain hash computation is deterministic. Test chain integrity verification (valid chain passes, corrupted chain fails). Test chain extension preserves prior entries.

- [ ] **Step 3:** Create `test/Test/Attestation.hs`. Test attestation record creation from scan result. Test attestation includes timestamp, actor, findings summary. Test signature verification concept (pure function).

- [ ] **Step 4:** Wire modules, run tests. Commit: "test: add evidence vault, evidence chain, and attestation tests"

---

### Task 24: Tests for Anomaly, AutoRemediate, Enforce

**Files:**
- Create: `test/Test/Anomaly.hs`
- Create: `test/Test/AutoRemediate.hs`
- Create: `test/Test/Enforce.hs`
- Modify: `orchestrator-enterprise.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/Anomaly.hs`. Test anomaly detection on workflow with unusual patterns (e.g., write-all permissions + no branch filter). Test normal workflow produces no anomalies. Test anomaly severity classification.

- [ ] **Step 2:** Create `test/Test/AutoRemediate.hs`. Test remediation plan generation from findings. Test rollback plan generation. Test dry-run mode produces plan but no actions.

- [ ] **Step 3:** Create `test/Test/Enforce.hs`. Test enforcement at Advisory level logs but doesn't block. Test Mandatory level reports. Test Blocking level prevents. Test fleet enforcement across multiple repos.

- [ ] **Step 4:** Wire modules, run tests. Commit: "test: add anomaly detection, auto-remediation, and enforcement tests"

---

### Task 25: Tests for Webhook, SupplyChain, MultiPlatform, Route

**Files:**
- Create: `test/Test/Webhook.hs`
- Create: `test/Test/EnterpriseSupplyChain.hs`
- Create: `test/Test/MultiPlatform.hs`
- Create: `test/Test/Route.hs`
- Modify: `orchestrator-enterprise.cabal`, `test/Main.hs`

- [ ] **Step 1:** Create `test/Test/Webhook.hs`. Test webhook payload construction for Slack format. Test PagerDuty payload format. Test generic HTTP payload. Test retry logic configuration. Test notification routing by severity.

- [ ] **Step 2:** Create `test/Test/EnterpriseSupplyChain.hs`. Test supply chain integrity check on workflow with pinned actions (pass). Test unpinned actions (flag). Test dependency provenance validation.

- [ ] **Step 3:** Create `test/Test/MultiPlatform.hs`. Test platform-specific config generation. Test cross-platform abstraction. Test platform detection logic.

- [ ] **Step 4:** Create `test/Test/Route.hs`. Test service routing configuration. Test route resolution. Test diff routing. Test Route.Types and Route.Config.

- [ ] **Step 5:** Wire all modules, run full suite. Commit: "test: add webhook, supply chain, multi-platform, and route tests"

---

### Task 26: Enterprise CI hardening + version consistency

**Files:**
- Modify: `.github/workflows/ci-haskell.yml` (ormolu, HLint, HPC, Haddock)
- Create: `.hlint.yaml`
- Modify: `Makefile` (expand targets)
- Modify: `CLAUDE.md` (fix version to 4.0.0)
- Modify: `docker-compose.yml` (fix version to 4.0.0)

- [ ] **Step 1:** Mirror CI hardening from Community Task 11.

- [ ] **Step 2:** Fix version references: CLAUDE.md 3.0.3 → 4.0.0, docker-compose.yml image tag 3.0.0 → 4.0.0.

- [ ] **Step 3:** Remove or create `scripts/fetch-dependencies.sh` (referenced in Makefile but missing). Either create a simple `cabal update && cabal build --only-dependencies` script, or remove the Makefile target.

- [ ] **Step 4:** Expand Makefile with coverage, haddock, bench targets.

- [ ] **Step 5:** Run full CI locally. Commit: "ci: harden CI, fix version consistency (4.0.0), add missing fetch-deps script"

---

### Task 27: Enterprise Dockerfile update

**Files:**
- Modify: `Dockerfile` (update version label, optimize)
- Modify: `docker-compose.yml` (version sync)

- [ ] **Step 1:** Update Dockerfile version labels and ensure build still works with current cabal file.

- [ ] **Step 2:** Update docker-compose.yml image version to match cabal version.

- [ ] **Step 3:** Test: `podman build -f Dockerfile -t orchestrator-enterprise:test .`

- [ ] **Step 4:** Commit: "chore: update Dockerfile and docker-compose.yml to v4.0.0"

---

## Phase 4: Cross-Edition Verification

### Task 28: Full verification across all three repos

- [ ] **Step 1:** In Community: `cabal clean && cabal build all --ghc-options="-Werror" && cabal test all --test-show-details=direct`

- [ ] **Step 2:** In Business: `cabal clean && cabal build all --ghc-options="-Werror" && cabal test all --test-show-details=direct`

- [ ] **Step 3:** In Enterprise: `cabal clean && cabal build all --ghc-options="-Werror" && cabal test all --test-show-details=direct`

- [ ] **Step 4:** Verify test counts:
  - Community: target 400+ tests (was 243)
  - Business: target 100+ tests (was 59)
  - Enterprise: target 300+ tests (was 175, but 9 files were unwired)

- [ ] **Step 5:** Run orchestrator self-scan on all three: `orchestrator scan .github/workflows/ --fail-on error`

---

## Expected Final Scorecard

| Dimension | Community | Business | Enterprise |
|:---|:---:|:---:|:---:|
| Type Safety | S | S | S |
| Tier Enforcement | S | S | S |
| Test Suite | S | S | S |
| Architecture | A+ | A+ | S |
| CI/CD | S | S | S |
| Policy Engine | A+ | A | A+ |
| Documentation | A+ | A | A |
| Packaging | A+ | A | S |
| Security | A | A | A+ |
| Developer UX | B+ | B+ | B+ |
| Output Formats | B+ | A+ | A+ |
| Remediation | C (gated) | A+ | A+ |
| Scalability | C (gated) | A+ | A+ |
| Observability | D (gated) | B+ | A+ |
| Governance | F (gated) | D (gated) | S |
| Compliance | F (gated) | F (gated) | S |

**Note:** Gated items remain at their tier-locked rating by design — these are architectural boundaries, not gaps. Within-scope dimensions all reach A+ or S.
