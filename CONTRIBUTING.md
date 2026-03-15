# Contributing to Haskell Orchestrator

Thank you for considering contributing to Haskell Orchestrator.

## Getting Started

1. Fork the repository
2. Clone your fork
3. Ensure GHC 9.6.x and Cabal 3.10+ are installed
4. Run `cabal update && cabal build all && cabal test all`
5. Create a feature branch from `main`

## Development Workflow

```bash
# Build
cabal build all

# Run tests
cabal test all --test-show-details=direct

# Run the demo
cabal run orchestrator -- demo

# Format (optional, recommended)
ormolu --mode inplace $(find src app test -name '*.hs')
```

## Pull Request Guidelines

- Keep changes focused and reviewable
- Add tests for new functionality
- Ensure all tests pass
- Follow existing code style
- Update documentation if behavior changes
- One logical change per PR

## Code Style

- GHC2021 language edition
- Strict fields in data types
- Qualified imports for non-Prelude modules
- Clear, descriptive names
- Module documentation with Haddock comments

## Adding Policy Rules

To add a new policy rule:

1. Add the rule function in `src/Orchestrator/Policy.hs`
2. Add it to `defaultPolicyPack`
3. Add test cases in `test/Test/Policy.hs`
4. Document the rule in `DESIGN.md`

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include reproduction steps for bugs
- Include expected vs. actual behavior

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
