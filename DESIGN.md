# Design Document — Haskell Orchestrator

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   CLI Layer                      │
│  (optparse-applicative, subcommands, flags)      │
└──────────┬──────────────────────────┬────────────┘
           │                          │
┌──────────▼──────────┐  ┌───────────▼────────────┐
│     Scan Engine     │  │    Demo Engine          │
│  (local paths,      │  │  (synthetic fixtures)   │
│   workflow files)    │  │                         │
└──────────┬──────────┘  └───────────┬────────────┘
           │                          │
┌──────────▼──────────────────────────▼────────────┐
│              Parser Layer                         │
│  (YAML → typed Workflow model via HsYAML)        │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│            Typed Domain Model                     │
│  Workflow, Job, Step, Permissions, Triggers,      │
│  ConcurrencyConfig, RunnerSpec                    │
└──────────┬───────────────────────┬───────────────┘
           │                       │
┌──────────▼──────────┐  ┌────────▼────────────────┐
│  Structural         │  │   Policy Engine          │
│  Validation         │  │  (rule packs, findings,  │
│  (empty jobs,       │  │   severity, categories)  │
│   dangling needs,   │  │                          │
│   duplicate IDs)    │  │                          │
└──────────┬──────────┘  └────────┬────────────────┘
           │                       │
┌──────────▼───────────────────────▼───────────────┐
│            Diff / Plan Engine                     │
│  (remediation steps, plan rendering)              │
└──────────────────────┬───────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────┐
│            Render Layer                           │
│  (text output, JSON output, summaries)            │
└──────────────────────────────────────────────────┘
```

## Typed Domain Model

The core of Orchestrator is a Haskell data model that captures the semantics
of GitHub Actions workflows:

- **Workflow** — top-level container with name, filename, triggers, jobs, permissions, concurrency, and environment.
- **Job** — a unit of work with ID, runner spec, steps, permissions, dependencies (needs), timeout, and concurrency.
- **Step** — a single action or shell command with optional uses, run, env, and conditional.
- **Permissions** — either a blanket level (read-all/write-all) or a fine-grained scope map.
- **WorkflowTrigger** — events (push, PR), cron schedules, or manual dispatch.
- **RunnerSpec** — standard GitHub runner, matrix expression, or custom label.

All types use strict fields for predictable memory behavior.

## Parser Design

The parser converts raw YAML (via the `yaml` library / `Data.Yaml`) into the
typed domain model.  Key design choices:

1. **Lenient parsing** — The parser accepts valid GitHub Actions YAML even
   when it contains features not yet modeled. Unknown keys are ignored.
2. **Structured errors** — Parse failures produce `OrchestratorError` values
   with file paths and descriptive messages.
3. **No execution** — The parser never evaluates expressions, resolves
   variables, or executes anything. It produces a static model.

## Policy Engine

The policy engine evaluates parsed workflows against a set of rules:

- Each rule has an ID, name, description, severity, category, and check function.
- Rules are grouped into named packs (e.g., "standard").
- The check function takes a `Workflow` and returns `[Finding]`.
- Findings include severity, category, rule ID, message, file, and remediation suggestion.

### Built-in Rules (Standard Pack)

| ID | Name | Severity | Category |
|----|------|----------|----------|
| PERM-001 | Permissions Required | Warning | Permissions |
| PERM-002 | Broad Permissions | Error | Permissions |
| RUN-001 | Self-Hosted Runner Detection | Info | Runners |
| CONC-001 | Missing Concurrency | Info | Concurrency |
| SEC-001 | Unpinned Actions | Warning | Security |
| SEC-002 | Secret in Run Step | Error | Security |
| RES-001 | Missing Timeout | Warning | Structure |
| NAME-001 | Workflow Naming | Info | Naming |
| NAME-002 | Job Naming Convention | Info | Naming |
| TRIG-001 | Wildcard Triggers | Info | Triggers |

## Rendering Model

Output is rendered through a dedicated layer that supports:

- **Text output** — Human-readable findings with severity tags, file paths, and remediation suggestions.
- **JSON output** — Machine-readable output for pipeline integration.
- **Summary** — Aggregated statistics by category and severity.
- **Plan rendering** — Step-by-step remediation plans.

## Scope Boundaries

### In Scope

- Parsing and validating GitHub Actions workflow YAML
- Policy-based evaluation of workflow correctness and hygiene
- Generating reports and remediation plans
- Demo mode with synthetic data

### Out of Scope

- Modifying workflow files (read-only by default)
- Executing workflows or actions
- Managing GitHub repositories or settings
- Monitoring CI/CD pipeline runs
- Real-time workflow analysis

## Performance Model

- **Default parallelism:** Conservative (1 worker or CPU count / 4).
- **Bounded pools:** Worker count is always explicitly bounded.
- **Memory:** Proportional to the number of workflow files being processed concurrently. Each parsed workflow is a small in-memory data structure.
- **I/O:** File reads are sequential per target. Network I/O (GitHub API) is bounded by configurable concurrency.
- **No background indexing:** Scan results are computed on demand, not cached.

## Configuration Design

Configuration uses a YAML file (`.orchestrator.yml`) with sections for:
- Scan targets and exclusions
- Policy pack selection and rule disabling
- Output format and verbosity
- Resource limits (jobs, parallelism profile)

All settings have sensible defaults.  The tool works with zero configuration.
