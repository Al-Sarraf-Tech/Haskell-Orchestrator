# Remediation Philosophy — Haskell Orchestrator

Author: Jamal Al-Sarraf

---

## Core Principles

Haskell Orchestrator follows three remediation principles that govern how
the tool interacts with your codebase:

1. **Read-only first**
2. **Plan before act**
3. **Dry-run by default**

These are not limitations — they are deliberate design choices that make
the tool trustworthy in production, CI, and security-sensitive environments.

---

## Read-Only First

The tool's primary mode of operation is analysis. Every command that
examines workflows — `scan`, `validate`, `diff`, `plan`, `demo`, `doctor`,
`rules`, `explain`, `verify` — is strictly read-only. No files are created,
modified, or deleted.

### Why Read-Only?

**Trust.** When you add a new tool to your CI pipeline or run it against
production repositories, the first question is: "What will it do to my
code?" The answer for Haskell Orchestrator is always "nothing." It reads
workflow files and produces text output. That is the entire surface area
of interaction.

**Safety.** Automated modification of CI/CD pipeline definitions is
inherently risky. A well-intentioned "fix" that adds explicit permissions
to a workflow could break a deployment if the permissions are too narrow.
A "fix" that pins an action to a commit SHA could pin to the wrong commit.
Automated fixes require human judgement to be correct.

**Auditability.** When changes are made manually after reviewing a plan,
there is a clear record of who made the change, when, and why. Automated
fixes obscure this chain of responsibility.

### What This Means in Practice

The tool will never:
- Rewrite your workflow YAML
- Create pull requests on your behalf
- Modify file permissions
- Delete or move files
- Commit changes to your repository

If you want a tool that auto-fixes issues, Haskell Orchestrator is not
that tool by design. It is an analysis and planning instrument that
empowers operators to make informed decisions.

---

## Plan Before Act

The `plan` command generates a structured remediation plan: a prioritised
list of findings with specific instructions for resolution. The plan is
not executed — it is presented for review.

### Why Plan First?

**Context matters.** A finding like "missing permissions block" has a
generic remediation ("add a permissions block"), but the correct
permissions depend on what the workflow actually does. A CI workflow needs
`contents: read`. A release workflow might need `contents: write` and
`packages: write`. The tool cannot know this from YAML structure alone.

**Priority matters.** Not all findings are equally urgent. A secret exposed
in a run step (SEC-002) is more critical than a non-kebab-case job ID
(NAME-002). The plan groups findings by priority so operators address
the most impactful issues first.

**Scope matters.** A team with 47 findings across 10 workflows cannot fix
everything in one sprint. The plan provides a structured way to triage
and schedule work. Fix the errors this week, the warnings next week, and
the info-level items as part of ongoing maintenance.

### Plan Structure

A typical plan is organised by priority level:

1. **Priority 1: Security and correctness errors.** These should be fixed
   immediately. They represent active risk (exposed secrets, overly broad
   permissions, unpinned actions).

2. **Priority 2: Warnings.** These should be fixed soon. They represent
   best-practice violations (missing timeouts, missing permissions blocks)
   that increase risk over time.

3. **Priority 3: Hygiene improvements.** These can be addressed during
   normal development. They represent naming conventions, concurrency
   optimisations, and informational observations.

Each item in the plan includes:
- The rule ID and severity
- The file where the issue was found
- A description of the problem
- Specific instructions for resolution

---

## Dry-Run by Default

Every operation in Haskell Orchestrator is effectively a dry run. There is
no `--execute`, `--apply`, or `--fix` flag. The tool shows you what it
found and what it recommends. You decide what to do.

### Why Dry-Run?

**Workflow files are infrastructure.** Modifying a CI/CD pipeline without
review is equivalent to modifying a production server configuration without
review. The consequences of a bad change range from broken builds to
security incidents.

**Reversibility.** If you review a plan and apply changes manually, you
can review each change in your editor, test it locally, and verify it in
a pull request. If the tool applied changes automatically, reverting a bad
change requires understanding what the tool did and why.

**Compatibility.** Different teams have different review processes, change
management policies, and approval workflows. An automated fix tool would
need to integrate with all of them. A plan that produces text output works
with any process.

---

## Deterministic Output

Given the same input files and the same configuration, Haskell Orchestrator
always produces the same findings and plans. There is no randomness, no
time-dependent logic, no external service dependency, and no
non-deterministic ordering in the output.

This means:
- CI results are reproducible across machines and runs.
- Plans can be regenerated and compared over time.
- Findings can be diffed across versions to detect regressions.
- Output is suitable for automated comparison and trending.

---

## Severity-Driven Prioritisation

Findings are ranked by severity:

| Severity | Meaning | Remediation Urgency |
|---|---|---|
| Critical | Immediate security or operational risk | Fix now |
| Error | Significant issue, should not be merged | Fix before merge |
| Warning | Best-practice violation | Fix in current sprint |
| Info | Improvement suggestion | Fix opportunistically |

Remediation plans prioritise higher-severity issues first. The default
minimum severity is Info (report everything). Operators can raise the
threshold to Warning or Error to focus on actionable items:

```yaml
policy:
  min_severity: warning
```

---

## The Remediation Workflow

The intended workflow is:

```
1. Scan      --> Discover issues
2. Validate  --> Confirm structural correctness
3. Diff      --> Review current state
4. Plan      --> Generate prioritised remediation plan
5. Review    --> Operator reviews the plan
6. Act       --> Operator makes changes manually
7. Verify    --> Re-scan to confirm issues are resolved
```

Steps 1-4 are automated. Step 5 is human judgement. Step 6 is manual
implementation. Step 7 is automated verification.

This workflow ensures that every change to workflow files is:
- Motivated by a specific finding
- Reviewed by a human
- Implemented with full context
- Verified by re-scanning

---

## Comparison to Auto-Fix Tools

Some tools in the linting and security space offer `--fix` flags that
automatically rewrite source files. This approach works well for:
- Code formatting (whitespace, indentation)
- Import sorting
- Simple syntactic transformations with no semantic ambiguity

It works poorly for:
- Permission scoping (requires understanding what the workflow does)
- Action pinning (requires choosing the correct commit SHA)
- Timeout values (requires understanding expected job duration)
- Concurrency configuration (requires understanding deployment strategy)

Haskell Orchestrator deals exclusively with the second category of
issues — ones where the correct fix requires human judgement. Providing
an auto-fix that guesses wrong would be worse than providing no auto-fix
at all.

---

## Business and Enterprise Extensions

The Business edition extends the remediation model with:
- **Effort estimates** — approximate time and complexity for each fix
- **Quick-fix vs. comprehensive strategies** — a quick fix addresses the
  immediate finding; a comprehensive strategy addresses the underlying
  pattern
- **Plan merging and deduplication** — when the same issue appears in
  multiple files, the plan consolidates them

The Enterprise edition extends the model further with:
- **Governance enforcement levels** — Advisory (report only), Mandatory
  (must be addressed), Blocking (prevents deployment until addressed)
- **Compliance artifact generation** — produces evidence documents for
  SOC 2, HIPAA, and other frameworks based on scan results

In all cases, the read-only-first, plan-before-act, dry-run-by-default
philosophy is preserved. Enterprise governance `enforce` performs checks
and reports violations; it does not automatically block or modify anything.

---

## Summary

| Principle | Implementation |
|---|---|
| Read-only first | No write operations in scan/validate/diff/plan |
| Plan before act | Structured, prioritised remediation plans |
| Dry-run by default | No `--fix`, `--apply`, or `--execute` flags |
| Deterministic output | Same input always produces same findings |
| Human in the loop | Plans are reviewed and applied manually |
| Verify after change | Re-scan confirms resolution |

This philosophy makes Haskell Orchestrator suitable for environments where
safety and control matter more than automation speed.
