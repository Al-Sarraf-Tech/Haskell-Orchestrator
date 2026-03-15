# Release Process

## Versioning

This project uses [Semantic Versioning](https://semver.org/).

## Creating a Release

1. Update `CHANGELOG.md` with release notes
2. Update version in `orchestrator.cabal`
3. Commit: `git commit -am "Release vX.Y.Z"`
4. Tag: `git tag vX.Y.Z`
5. Push: `git push origin main --tags`
6. GitHub Actions will automatically:
   - Build the release binary
   - Run the full test suite
   - Generate checksums and SBOM
   - Create a GitHub Release with artifacts

## Pre-Release Checklist

- [ ] All tests pass: `cabal test all`
- [ ] Demo works: `cabal run orchestrator -- demo`
- [ ] Release gate passes: `make release-gate`
- [ ] CHANGELOG.md is updated
- [ ] Version is bumped in .cabal file
- [ ] No prohibited content: `make release-gate`

## Release Artifacts

Each release includes:
- `orchestrator-X.Y.Z-linux-x86_64` — compiled binary
- `SHA256SUMS-X.Y.Z.txt` — checksums
- `sbom-X.Y.Z.json` — CycloneDX SBOM
- Build provenance attestation (GitHub-native)
