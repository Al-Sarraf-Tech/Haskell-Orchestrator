# Tier Expansion Design: Community, Business, Enterprise

**Date:** 2026-04-07
**Status:** Approved
**Version:** 1.0

## Overview

Expand all three Haskell Orchestrator tiers into a layered value chain:

| Tier | Value Type | Buyer Persona |
|------|-----------|---------------|
| Community (Free) | **Detection** — "what's wrong" | Individual devs, small teams |
| Business (Paid) | **Action** — "fix it at scale" | Platform eng leads, DevOps owners (10-200 repos) |
| Enterprise (Paid) | **Proof** — "prove we're compliant" | Security/compliance leads, auditors |

Each tier genuinely builds on the one below, but the *kind* of value changes at each level. Community drives adoption. Business saves teams time. Enterprise satisfies regulators.

All repos (personal and org) will run the Orchestrator as a CI check. The Orchestrator dogfoods itself — each edition scans its own workflows.

---

## 1. Community Edition — The Detection Engine

### Philosophy

Make Community the best free GitHub Actions linter. 36 rules (21 existing + 15 new), dead-simple CI integration, and a safety-first read-only model.

### New Rules

#### Supply Chain Security

| Rule ID | Name | Severity | Detection |
|---------|------|----------|-----------|
| SEC-003 | Workflow Run Privilege Escalation | Error | `workflow_run` triggered from forks accessing secrets — detects unsafe `workflow_run` + `pull_request_target` patterns |
| SEC-004 | Artifact Poisoning | Warning | Downloading artifacts from untrusted workflows and executing without verification |
| SEC-005 | OIDC Token Scope | Warning | `id-token: write` granted without a deployment step consuming it |
| SUPPLY-001 | Abandoned Action | Warning | Action repo archived or no commits in 12+ months (checked against compiled-in catalog) |
| SUPPLY-002 | Typosquat Risk | Info | Action name suspiciously similar to a popular action (edit distance check) |

#### Performance & Cost

| Rule ID | Name | Severity | Detection |
|---------|------|----------|-----------|
| PERF-001 | Missing Cache | Warning | Build workflows (Node, Rust, Haskell, Go, Python) without `actions/cache` or built-in caching |
| PERF-002 | Sequential Parallelizable Jobs | Info | Jobs with no `needs:` dependencies running sequentially when they could parallelize |
| COST-001 | Matrix Waste | Warning | Matrix includes entries immediately excluded — wasted runner starts |
| COST-002 | Redundant Artifact Upload | Info | Multiple jobs uploading artifacts with overlapping paths |

#### Hardening & Best Practices

| Rule ID | Name | Severity | Detection |
|---------|------|----------|-----------|
| HARD-001 | Missing persist-credentials: false | Warning | Checkout without `persist-credentials: false` — token lingers in git config |
| HARD-002 | Default Shell Unset | Info | Top-level `defaults.run.shell` not set — platform-dependent behavior |
| HARD-003 | Pull Request Target Risk | Error | `pull_request_target` with checkout of PR head — code execution from untrusted fork |
| DRIFT-001 | Intra-Repo Inconsistency | Info | Same action used at different versions across workflows in one repo |

#### Structural

| Rule ID | Name | Severity | Detection |
|---------|------|----------|-----------|
| STRUCT-001 | Unreferenced Reusable Workflow | Info | Reusable workflow in `.github/workflows/` never called by any other workflow |
| STRUCT-002 | Circular Workflow Call | Error | Reusable workflow A calls B calls A (cross-workflow cycle detection) |

### New Community Features

- **GitHub Action** (`Al-Sarraf-Tech/orchestrator-action@v3`) — one-line CI integration, SARIF output, configurable fail threshold
- **Exit code gating** — `--fail-on warning|error|critical` for CI pass/fail control
- **Rule tagging** — rules tagged by category (`security`, `performance`, `cost`, `style`, `structure`) for selective scanning via `--tags`
- **Suppression comments** — `# orchestrator:disable SEC-001` inline in workflow YAML to suppress specific findings per-line
- **Action catalog** — compiled-in curated list of known-good actions with metadata (maintained, verified publisher, pinned SHA available)

### New Community Modules

```
src/Orchestrator/
  Rules/
    SupplyChain.hs       # SEC-003, SEC-004, SEC-005, SUPPLY-001, SUPPLY-002
    Performance.hs       # PERF-001, PERF-002
    Cost.hs              # COST-001, COST-002
    Hardening.hs         # HARD-001, HARD-002, HARD-003
    Drift.hs             # DRIFT-001
    Structure.hs         # STRUCT-001, STRUCT-002
  Suppress.hs            # Inline suppression comment parser
  Tags.hs                # Rule tagging system
  Gate.hs                # --fail-on exit code logic
```

---

## 2. Business Edition — The Action Engine

### Philosophy

Community tells you what's wrong. Business helps you fix it at scale, track progress, and save your team time.

### Multi-Repo Operations

- **Batch scanning** — `orchestrator batch scan --org Al-Sarraf-Tech` scans all repos (1-32 parallel workers)
- **Diff-aware scanning** — `orchestrator scan --diff HEAD~1` only analyzes changed workflows in PRs
- **Repo grouping** — named groups in config (`backend-services`, `frontend-apps`), scan/report per group

### PR Integration

- **PR comment bot** — `orchestrator pr-comment` posts findings as structured GitHub PR comment with inline annotations
- **PR status check** — configurable pass/fail threshold, integrates as GitHub Check Run
- **Fix suggestions in PR** — auto-generated GitHub suggestion blocks for one-click reviewer acceptance

### Reporting & Dashboards

- **HTML report** — self-contained single-file HTML with sortable tables, severity breakdown, per-repo drill-down
- **CSV export** — for spreadsheet analysis, Jira import, custom tooling
- **Summary statistics** — JSON blob of totals by severity, category, repo
- **Trend tracking** — append-only JSONL history, `orchestrator trend show` renders improvement/regression over time
- **Burndown view** — "47 findings last month, 31 this month, on track to zero by Q3"

### Optimization Intelligence

| Feature | What It Does |
|---------|-------------|
| CI cost estimation | Estimates runner-minutes per workflow (job count, matrix size, runner labels). User-configurable cost threshold for flagging expensive workflows |
| Parallelization advisor | Analyzes job DAG, recommends restructuring to reduce wall-clock time |
| Cache impact estimator | Estimates time saved by adding caching (language/framework heuristics) |
| Runner right-sizing | Detects `ubuntu-latest` jobs that could use smaller runners, or jobs needing larger |
| Workflow consolidation | Detects multiple workflows on same trigger that could merge to reduce overhead |

### Policy Bundles

Pre-built rule configurations:

- **`security-hardened`** — all security rules at Error, pinning enforced, permissions mandatory
- **`cost-optimized`** — performance/cost rules at Warning, matrix explosion at Error
- **`startup-fast`** — minimal rules (Error-severity security only), no style checks
- **`enterprise-ready`** — prepares repos for Enterprise (governance, environment gates, audit readiness)

### Plan Merging

- **Cross-repo plan** — `orchestrator batch plan` produces unified remediation across repos, deduplicated
- **Effort estimation** — each step tagged: `quick-fix` (< 5 min), `moderate` (< 30 min), `significant` (> 30 min)
- **Fix ordering** — severity first, then effort (quick wins first), then blast radius

### New Business Modules

```
src/OrchestratorBusiness/
  Batch.hs                # Multi-repo scanning with parallel workers
  Batch/RepoGroup.hs      # Named repo groups, group-level config
  Report.hs               # HTML + CSV report generation
  Report/Html.hs          # Self-contained single-file HTML report
  Report/Csv.hs           # CSV export
  Trend.hs                # JSONL append-only history, trend analysis
  Trend/Burndown.hs       # Burndown projection
  PR.hs                   # PR comment generation, Check Run integration
  PR/Suggestion.hs        # GitHub suggestion block generation
  Optimize.hs             # Optimization intelligence entry point
  Optimize/CostEstimate.hs    # Runner-minute estimation
  Optimize/Parallelization.hs # Job graph restructuring suggestions
  Optimize/Cache.hs           # Cache impact estimation
  Optimize/RunnerSizing.hs    # Runner right-sizing recommendations
  Optimize/Consolidation.hs   # Workflow merge opportunities
  PolicyBundle.hs          # Pre-built policy configurations
  Plan/Merge.hs            # Cross-repo plan merging/dedup
  Plan/Effort.hs           # Effort estimation
  DiffAware.hs             # Git-diff-aware scanning
```

---

## 3. Enterprise Edition — The Proof Engine

### Philosophy

Business tells your team what to fix. Enterprise proves to auditors, executives, and regulators that you did.

### Governance Engine

| Feature | Description |
|---------|-------------|
| Governance policies | Named policies with enforcement: `Advisory` (log), `Mandatory` (warn + track), `Blocking` (fail CI) |
| Policy scoping | `AllRepos`, `RepoPattern("backend-*")`, `SpecificRepos(["api-gateway"])` |
| Policy inheritance | Cascading org -> team -> repo. Repo overrides can tighten but never loosen |
| Policy simulation | `orchestrator governance simulate --policy X` dry-runs against all repos before enforcing |
| Enforcement timeline | "Becomes Blocking on 2026-07-01" — scheduled severity escalation |

### Audit System

| Feature | Description |
|---------|-------------|
| Immutable audit trail | Append-only log of every scan, policy change, enforcement action, exception grant |
| Tamper evidence | SHA-256 hash chain per entry — any modification detectable |
| Audit log export | `orchestrator audit export --format json|csv --since DATE` for SIEM/GRC |
| Exception tracking | Formal grants: "SEC-001 suppressed for repo X until DATE, approved by Y, reason: Z" |
| Retention policies | Configurable retention (default 2 years), export-before-purge enforcement |

### Compliance Frameworks

| Feature | Description |
|---------|-------------|
| SOC 2 Type II mapping | Rules mapped to Trust Service Criteria (SEC-001 -> CC6.1, PERM-001 -> CC6.3) |
| HIPAA Security Rule | Rules mapped to 164.312 Technical Safeguards |
| Custom frameworks | Define your own compliance framework with custom control IDs and rule mappings |
| Per-repo compliance score | 0-100, weighted by finding severity, aggregated per-group |
| Evidence vault | `orchestrator compliance evidence --framework soc2 --period Q1-2026` — tamper-evident signed archive |
| Compliance trend | Score over time: "72% in January, 89% in March" |

### Risk & Drift

| Feature | Description |
|---------|-------------|
| Risk scoring | 0-100 per repo, weighted by severity/count/category. Aggregated to org |
| Drift detection | Compare current scan against last known-good baseline, flag regressions |
| Regression alerting | Score drop or new Critical/Error findings triggers notifications |
| Webhook notifications | Slack, PagerDuty, Microsoft Teams, generic HTTP |
| Alert routing | By severity: Info -> Slack, Error -> team lead, Critical -> PagerDuty |

### Access Control & Administration

| Feature | Description |
|---------|-------------|
| RBAC | PolicyAdmin, Auditor, Operator, Viewer |
| Org-wide commands | `orchestrator admin enforce`, `admin scan-all`, `admin export` |
| Executive reporting | One-page: org compliance score, top-risk repos, trend arrows, deadlines |
| Policy changelog | Git-style history of all policy modifications (who/when/why) |

### New Enterprise Modules

```
src/OrchestratorEnterprise/
  Governance.hs                # Policy engine entry point
  Governance/Policy.hs         # Policy types (Advisory/Mandatory/Blocking)
  Governance/Scope.hs          # AllRepos, RepoPattern, SpecificRepos
  Governance/Inheritance.hs    # Org -> team -> repo cascading
  Governance/Simulate.hs       # Dry-run policy evaluation
  Governance/Timeline.hs       # Scheduled enforcement escalation
  Audit.hs                     # Audit trail entry point
  Audit/Trail.hs               # Append-only log with hash chain
  Audit/Export.hs              # JSON/CSV export
  Audit/Exception.hs           # Formal exception grants with expiry
  Audit/Retention.hs           # Retention policies, export-before-purge
  Compliance.hs                # Compliance framework entry point
  Compliance/Framework.hs      # Framework definition type
  Compliance/Mapping.hs        # Rule -> control mapping
  Compliance/Score.hs          # Per-repo 0-100 scoring
  Compliance/Evidence.hs       # Evidence vault signed archives
  Compliance/Trend.hs          # Score tracking over time
  Risk.hs                      # Risk scoring engine
  Risk/Score.hs                # Weighted scoring
  Risk/Drift.hs                # Baseline regression detection
  Notify.hs                    # Notification dispatch
  Notify/Slack.hs              # Slack webhook
  Notify/PagerDuty.hs          # PagerDuty events
  Notify/Teams.hs              # Microsoft Teams webhook
  Notify/Http.hs               # Generic HTTP webhook
  RBAC.hs                      # Role-based access control
  RBAC/Roles.hs                # Role definitions
  Admin.hs                     # Org-wide admin commands
  Executive.hs                 # Executive summary reports
```

---

## 4. CI Integration Model

### Layer 1: GitHub Action (Community)

```yaml
- uses: Al-Sarraf-Tech/orchestrator-action@v3
  with:
    fail-on: warning
    format: sarif
    config: .orchestrator.yml
```

Downloads pre-built binary (cached), scans `.github/workflows/`, outputs findings, uploads SARIF to GitHub Code Scanning, sets exit code based on threshold, posts job summary.

### Layer 2: Reusable Workflow (Business)

```yaml
jobs:
  orchestrator:
    uses: Al-Sarraf-Tech/orchestrator-workflows/.github/workflows/scan.yml@v3
    with:
      fail-on: error
      pr-comment: true
      trend-file: .orchestrator-trend.jsonl
      policy-bundle: security-hardened
    secrets: inherit
```

### Layer 3: Org-Wide Enforcement (Enterprise)

Scheduled nightly workflow running `admin scan-all` with governance config, audit export, and Slack/PagerDuty notifications.

### Gating Strategies

| Strategy | `fail-on` | Behavior | Use Case |
|----------|-----------|----------|----------|
| Advisory | `none` | Never fails CI | Initial adoption, brownfield |
| Moderate | `error` | Fails on Error/Critical | Most teams post-cleanup |
| Strict | `warning` | Fails on Warning+ | Security-sensitive, greenfield |

---

## 5. Dogfooding Model

### Self-Check

Each edition repo runs its own tier's binary against its own workflows in CI:

- Community: scanned by Community (36 rules)
- Business: scanned by Business (36 rules + batch/reporting checks)
- Enterprise: scanned by Enterprise (36 rules + governance/compliance checks)

Added as `orchestrator-self-check` job in each repo's CI workflow, gated at `--fail-on warning`.

### Baseline Commitment

Checked-in `.orchestrator-baseline.json` in each repo. CI fails on new findings beyond baseline — ratchet-forward only.

---

## 6. Testing & Quality Strategy

### Test Pyramid

```
                    E2E Tests
                  Integration Tests
                Unit + Golden Tests
              Property Tests (QuickCheck)
```

### Test Categories

#### Unit Tests (~250 target)

Every rule gets:
- Positive detection (fires on violation)
- Negative detection (clean workflow passes)
- Severity correctness
- Remediation text presence
- Edge cases (empty workflows, missing fields)
- Suppression respect

36 rules x ~6 tests = ~216 rule tests + parser/model/config unit tests.

#### Property Tests (30+ target)

| Property | Invariant |
|----------|-----------|
| Parse roundtrip | `parse . render == id` for all generated workflows |
| Rule determinism | Same workflow -> same findings, always |
| Rule monotonicity | Adding a violation never reduces finding count |
| Severity ordering | `Info < Warning < Error < Critical` |
| Finding completeness | Every finding has non-empty ruleId, message, remediation |
| Config stability | Default config == no config |
| Baseline idempotence | Baseline of clean scan -> empty diff on re-scan |
| Graph acyclicity | Topo sort succeeds iff no cycles |
| Suppression soundness | Suppressed rule never in findings |
| Tag filtering | `--tags security` produces only security-tagged findings |

#### Integration Tests (40+ target)

- Full scan pipeline (YAML -> ScanResult with expected findings)
- Multi-file scan (directory -> aggregated findings)
- Config override (custom `.orchestrator.yml` modifies behavior)
- Baseline comparison (new detected, resolved removed)
- Output format parity (JSON, SARIF, Markdown, Text same findings)
- Exit code correctness (`--fail-on` -> correct exit codes)
- CLI argument parsing (every flag and subcommand)
- Concurrent scanning (parallel -> deterministic results)

#### Golden Tests (50+ target)

- One golden file per output format per fixture
- Golden for `orchestrator rules` table
- Golden for `orchestrator explain RULE-ID` per rule
- Golden for demo output

#### E2E Tests (30+ target)

- 20+ curated real-world workflow fixtures
- Regression suite (every bug fix gets a reproducing fixture)
- Binary smoke tests (`--version`, `--help`, `doctor`)
- Demo mode clean run
- Cross-platform (Linux + Windows)

#### Tier Boundary Tests (10+ target)

- Import fence (Community has zero Business/Enterprise imports)
- Capability contract (every claimed capability has module + test)
- Feature flag isolation (Business features don't compile in Community)
- CLI surface (each binary exposes exactly its contracted commands)

### Test Count Summary

| Category | Existing | Target |
|----------|----------|--------|
| Unit | ~60 | ~250 |
| Property | 12 | 30+ |
| Integration | 10 | 40+ |
| Golden | ~5 | 50+ |
| E2E | 0 | 30+ |
| Tier boundary | 2 scripts | 10+ |
| **Total** | **~87** | **400+** |

### Linting & Static Analysis CI Gates

| Tool | Purpose | Gate |
|------|---------|------|
| HLint | Haskell idiom suggestions | `--fail-on suggestion` |
| Ormolu | Deterministic formatting | `--mode check` |
| GHC `-Werror` | Zero compiler warnings | Yes |
| Weeder | Dead code detection | Yes |
| Stan | Static analysis anti-patterns | Yes |
| Cabal check | Package metadata | Yes |
| ShellCheck | Bash script linting | Yes |
| actionlint | GitHub Actions workflow linting | Yes |
| Orchestrator | Self-check dogfooding | Yes |

### CI Pipeline Shape

```
Format (ormolu) ─┐
Lint (hlint)    ─┤──> Unit + Golden ─┐
Build (cabal)   ─┘    Property       ─┤──> Integration ──> E2E ──> Self-Check ──> Tier Boundary
```

---

## 7. Cross-Repo Synchronization

### Sync Model

Community is the source of truth for shared code. Business and Enterprise inline Community source.

```
Community (public, MIT)
  ├──> Business (private) — copies Community src/Orchestrator/ + adds OrchestratorBusiness/
  └──> Enterprise (private) — copies Community src/Orchestrator/ + adds OrchestratorEnterprise/
```

### Sync Process

1. Community changes land first
2. `scripts/sync-community.sh` copies `src/Orchestrator/**` into Business/Enterprise, preserving tier modules
3. Both repos run `check-tier-boundaries.sh` after sync
4. `COMMUNITY_VERSION` file in Business/Enterprise tracks synced version

### Sync Safety

- Copy, not submodule — each repo compiles independently
- Type changes in Community flagged by sync, CI fails until adapted
- Never sync Business/Enterprise changes back to Community

---

## 8. Release Strategy

### Phased Rollout

| Phase | Duration | Ships | Milestone |
|-------|----------|-------|-----------|
| 1 | 4 weeks | Community: 15 new rules, suppression, tags, `--fail-on`, GitHub Action | Community v4.0.0 |
| 2 | 4 weeks | Community: action catalog, dogfooding. Business: batch, diff-aware, trend | Business v1.0.0 |
| 3 | 4 weeks | Business: PR bot, HTML reports, optimization, policy bundles | Business v1.1.0 |
| 4 | 6 weeks | Enterprise: governance, audit, compliance, risk scoring | Enterprise v1.0.0 |
| 5 | 4 weeks | Enterprise: RBAC, notifications, evidence vault, executive reports | Enterprise v1.1.0 |
| 6 | 2 weeks | All: hardening, performance, docs, cross-repo CI | GA polish |

### Version Strategy

- Community: v3.0.4 -> v4.0.0 (major — new rules may flag previously clean repos)
- Business: v1.0.0 (new product)
- Enterprise: v1.0.0 (new product)
- Independent version numbers per tier
- Capability contract version tracks cross-tier compatibility

---

## 9. Documentation Strategy

| Document | Community | Business | Enterprise |
|----------|-----------|----------|------------|
| Quick Start | Install + first scan | Batch + PR integration | Governance + first audit |
| Operator Guide | CI integration, gating | Multi-repo mgmt, optimization | Policy design, compliance workflows |
| Rule Reference | 36 rules with examples | + optimization advisors | + governance policies |
| FAQ | Extend 22 existing | +15 Business-specific | +15 Enterprise-specific |
| API Reference | CLI flags + JSON schema | + batch/trend/PR APIs | + governance/audit/compliance APIs |
| Migration Guide | v3 -> v4 changes | Community -> Business | Business -> Enterprise |
| Example Configs | `.orchestrator.yml` | `batch.yml`, `policy-bundle.yml` | `governance.yml`, `compliance.yml` |
| Dogfooding Guide | How self-check works | How self-check works | How self-check works |

---

## 10. Security Considerations

| Feature | Risk | Mitigation |
|---------|------|------------|
| Action catalog | Stale/poisoned data | Compiled-in, updated via versioned releases only. Never runtime fetch. |
| PR comment bot | GitHub token with write access | Minimum privilege: `pull-requests: write` only. Token never logged. |
| Webhook notifications | URLs are secrets | Stored in config, never in audit logs. HTTPS only, no internal IPs. |
| Audit hash chain | Chain break loses integrity | Verification on every append. `audit verify` command. |
| Evidence vault | Archive forgery | Ed25519 signing with org-managed key. Verification documented. |
| RBAC | Role escalation | Roles in config, not self-assignable. No runtime modification. |

### Principles Carried Forward

- Read-only by default (only `fix --write` and `pr-comment` modify external state)
- No network by default (Community never phones home)
- No secrets in output (findings show presence, not values)
- All file I/O wrapped with `Control.Exception.try`

---

## 11. Performance Targets

| Scenario | Target |
|----------|--------|
| Single repo, 10 workflows | < 2 seconds |
| Single repo, 100 workflows | < 10 seconds |
| Batch, 50 repos (8 workers) | < 5 minutes |
| Batch, 200 repos (32 workers) | < 15 minutes |
| Enterprise org-wide, 500 repos | < 30 minutes (nightly) |

### Strategy

- Lazy YAML parsing (only fields rules need)
- Parallel rule evaluation (rules are pure functions)
- Batch worker pool (bounded semaphore, 1-32 workers)
- Incremental scanning (diff-aware skips unchanged files)
- Compiled-in catalog (Haskell map, not runtime file read)

---

## 12. Scope Summary

| | Community | Business | Enterprise |
|---|---|---|---|
| Rules | 36 (21 + 15 new) | 36 + advisors | 36 + governance |
| New modules | ~8 | ~18 | ~25 |
| Test target | 400+ total | +100 Business | +100 Enterprise |
| CI gates | 9 | +tier boundary | +tier boundary |
| New CLI commands | `--fail-on`, `--tags` | `batch`, `trend`, `pr-comment` | `governance`, `audit`, `compliance`, `admin` |
