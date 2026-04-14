# Haskell Orchestrator — Architecture

Version 3.0.3 | Community Edition | GHC 9.6.7 / GHC2021

---

## 1. System Overview

```mermaid
flowchart LR
    A[YAML Input\n.github/workflows/*.yml] --> B[Parser\nOrchestrator.Parser]
    B --> C[Domain Model\nOrchestrator.Model\nOrchestrator.Types]
    C --> D[Structural Validation\nOrchestrator.Validate\nOrchestrator.Graph]
    C --> E[Policy Engine\nOrchestrator.Policy\nOrchestrator.Rules.*]
    D --> F[Findings\nFinding · Severity\nFindingCategory]
    E --> F
    F --> G[Baseline Filter\nOrchestrator.Baseline]
    G --> H[Renderer\nOrchestrator.Render]
    H --> I1[Text / JSON]
    H --> I2[SARIF v2.1.0]
    H --> I3[Markdown]
```

The tool is purely read-only. No workflow file is modified unless `fix --write` is explicitly passed.

---

## 2. Module Dependency Graph

```mermaid
graph TD
    subgraph Core
        TY[Types]
        MO[Model]
        PA[Parser]
        CF[Config]
    end

    subgraph Analysis
        VA[Validate]
        GR[Graph]
        CX[Complexity]
        BL[Baseline]
        SC[Scan]
    end

    subgraph Policy
        PO[Policy]
        PE[Policy.Extended]
        RS[Rules.Structure]
        RR[Rules.Reuse]
        RM[Rules.Matrix]
        RE[Rules.Environment]
        RC[Rules.Composite]
        RD[Rules.Duplicate]
        RH[Rules.Hardening]
        RSupply[Rules.SupplyChain]
        RDrift[Rules.Drift]
        RPerf[Rules.Performance]
        RCost[Rules.Cost]
    end

    subgraph Output
        RN[Render]
        RMD[Render.Markdown]
        RSA[Render.Sarif]
        RU[Render.Upgrade]
        FO[Formatter]
    end

    subgraph Auxiliary
        DI[Diff]
        FX[Fix]
        TA[Tags]
        SU[Suppress]
        SE[Secrets]
        HK[Hook]
        SI[Simulate]
        GH[GitHub]
        UI[UI]
        LS[LSP]
    end

    subgraph CLI
        MA[Main]
        CL[CLI]
    end

    PA --> MO
    PA --> TY
    MO --> TY
    CF --> TY

    VA --> MO
    VA --> TY
    GR --> MO
    CX --> MO
    BL --> TY
    SC --> PA
    SC --> VA
    SC --> PO
    SC --> BL

    PO --> MO
    PO --> TY
    PO --> CF
    PE --> PO
    PE --> MO
    RS --> MO
    RS --> TY
    RR --> MO
    RM --> MO
    RE --> MO
    RC --> MO
    RD --> MO
    RH --> MO
    RSupply --> MO
    RDrift --> MO
    RPerf --> MO
    RCost --> MO

    RN --> TY
    RMD --> TY
    RSA --> TY
    FO --> TY

    DI --> TY
    DI --> PO
    FX --> MO
    FX --> TY
    TA --> TY
    SU --> TY

    MA --> CL
    MA --> SC
    MA --> PO
    MA --> PE
    MA --> RN
    MA --> DI
    MA --> BL
    MA --> GH
    MA --> UI
    CL --> TY
```

---

## 3. Edition Architecture

Each edition is a standalone binary. No runtime or build dependencies cross edition boundaries. Business and Enterprise inline their own copies of all required source.

```mermaid
graph TD
    subgraph community["Community (MIT, public)"]
        C_CORE["Core engine\nParser · Validate · Graph\nPolicy (10 rules) · Extended (11 rules)\nRender · Diff · Baseline · Fix"]
    end

    subgraph business["Business (private license)"]
        B_EXTRA["+ Multi-repo batch scanning\n+ Team policy rules (4)\n+ HTML/CSV reporting\n+ Prioritised remediation\n+ Diff-aware scanning\n+ PR comment integration\n+ Policy bundles\n+ Trend tracking"]
        B_CORE["Inlines Community source"]
    end

    subgraph enterprise["Enterprise (private license)"]
        E_EXTRA["+ Governance enforcement (Advisory/Mandatory/Blocking)\n+ Org-wide scanning\n+ Immutable audit trail\n+ SOC 2 / HIPAA compliance mapping\n+ Risk scoring + heatmap\n+ Policy inheritance (org → team → repo)\n+ Drift detection\n+ RBAC (Admin/Auditor/Operator/Viewer)\n+ Evidence vault\n+ Webhook notifications"]
        E_CORE["Inlines Community source"]
    end

    community -.->|source inlined, no runtime dep| business
    community -.->|source inlined, no runtime dep| enterprise
```

Tier boundary enforcement is enforced at build time by `scripts/check-tier-boundaries.sh`, which blocks any import of Business or Enterprise modules from Community source.

---

## 4. Data Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as CLI (Main/CLI.hs)
    participant Scan as Orchestrator.Scan
    participant Parser as Orchestrator.Parser
    participant Validate as Orchestrator.Validate
    participant Policy as Orchestrator.Policy
    participant Diff as Orchestrator.Diff
    participant Baseline as Orchestrator.Baseline
    participant Render as Orchestrator.Render

    User->>CLI: orchestrator scan PATH [--fail-on SEVERITY] [--tags TAG] [--baseline FILE]
    CLI->>Scan: discover *.yml under PATH
    Scan->>Parser: parse each YAML file
    Parser-->>Scan: Workflow (typed domain model)
    Scan->>Validate: checkStructure Workflow
    Validate-->>Scan: [Finding] (structural)
    Scan->>Policy: evaluatePolicies packs Workflow
    Policy-->>Scan: [Finding] (policy violations)
    Scan->>Scan: filter by --tags, deduplicate
    Scan->>Baseline: subtract saved baseline
    Baseline-->>Scan: [Finding] (net-new only)
    Scan->>Diff: buildPlan [Finding]
    Diff-->>Scan: Plan (ordered remediation steps)
    Scan->>Render: renderFindings mode findings plan
    Render-->>CLI: formatted output (Text/JSON/SARIF/Markdown)
    CLI-->>User: stdout + exit code (0 or 1 if --fail-on triggered)
```

---

## 5. Rule Evaluation Pipeline

Policy rules are pure functions — no IO, no state, fully deterministic.

```
PolicyPack
  packName  :: Text
  packRules :: [PolicyRule]
      │
      ▼
PolicyRule
  ruleId       :: Text          -- e.g. "PERM-001"
  ruleName     :: Text
  ruleSeverity :: Severity      -- Info | Warning | Error | Critical
  ruleCategory :: FindingCategory
  ruleTags     :: [RuleTag]     -- security | performance | cost | style | structure
  ruleCheck    :: Workflow -> [Finding]
      │
      │  applied to each parsed Workflow
      ▼
[Finding]
  findingSeverity    :: Severity
  findingRuleId      :: Text
  findingMessage     :: Text
  findingRemediation :: Text
  findingWorkflow    :: Text     -- source file
  findingJob         :: Maybe Text
      │
      ├─ filtered by --tags (RuleTag intersection)
      ├─ filtered by --fail-on (Severity threshold for exit code)
      ├─ subtracted against baseline (Orchestrator.Baseline)
      └─ rendered (Orchestrator.Render / Render.Sarif / Render.Markdown)
```

Built-in packs:

| Pack | Source | Rules |
|---|---|---|
| Standard | `Orchestrator.Policy` | 10 (PERM-001/002, SEC-001/002, RUN-001, CONC-001, RES-001, NAME-001/002, TRIG-001) |
| Extended | `Orchestrator.Policy.Extended` + `Rules.*` | 11 (graph, reuse, matrix, env, composite, duplicate, hardening, supply-chain, drift, performance, cost) |

Total: 36 rules in Community edition (21 core + 15 from extended rule modules).

---

## 6. CI Pipeline Architecture

```mermaid
flowchart TD
    PUSH[git push / PR] --> GUARD

    subgraph reusable["repo-guard.yml (reusable)"]
        GUARD[Repo ownership check\nThermal safety gate\n90°C hard limit on amarillo]
    end

    GUARD --> BUILD

    subgraph ci["ci-haskell.yml"]
        BUILD[cabal build all]
        TEST[cabal test all\n115 tests]
        LINT[cabal build --ghc-options=-Werror\nweeder dead-code check\normolu format check]
        CAP[capability-contract check\nyaml vs. code vs. CLI]
        BUILD --> TEST --> LINT --> CAP
    end

    subgraph sec["security-haskell.yml"]
        AUDIT[cabal audit\ndep vulnerability scan]
        SECRET[trufflehog\nsecret scan]
        ATTRIB[attribution check]
        AUDIT --> SECRET --> ATTRIB
    end

    subgraph standalone["build-standalone.yml"]
        SBIN[standalone binary build\nno external runtime deps]
    end

    CAP --> GATE{All checks pass?}
    sec --> GATE
    standalone --> GATE

    GATE -->|Tag push vX.Y.Z| REL

    subgraph release["release-haskell.yml"]
        RBIN[Build Linux binary\nBuild Windows binary]
        SBOM[Generate SBOM]
        GHCR[Push container image\nto GHCR]
        HADDOCK[Publish Haddock\nto GitHub Pages]
        RBIN --> SBOM --> GHCR --> HADDOCK
        HADDOCK --> RELEASE[GitHub Release\n+ binaries + SBOM]
    end
```

All workflows run on `[self-hosted, Linux, X64, haskell, unified-all]`. No macOS or Windows build runners.
