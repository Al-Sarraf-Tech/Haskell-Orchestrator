# Workspace Isolation — Haskell Orchestrator

## Isolation Statement

This repository is **completely isolated** from all external code:

- It does not depend on, reference, import from, or scan any repository
  outside its own tree.
- It does not perform automatic repository discovery on the filesystem.
- It does not crawl the home directory or any parent directory.
- All test fixtures, demo data, and examples are synthetic and self-contained.
- No external repository was used as a reference, template, or data source
  during development.

## Scope

This isolation applies to:
- All existing repositories on any machine where this code resides
- All future repositories
- All home-directory code
- All operator projects not explicitly specified as scan targets at runtime

## Runtime Behavior

At runtime, the tool only accesses paths or GitHub references that the
operator explicitly provides via command-line arguments or configuration.
There is no "discover all repos" mode.
