# Release Assertions — Haskell Orchestrator

This document describes the properties of release artifacts and the evidence
that supports each claim.

## Artifact Properties

### Binary Artifacts

| Property | Assertion | Evidence |
|----------|-----------|----------|
| Architecture | x86_64 Linux | Built on ubuntu-latest GitHub runner |
| Compiler | GHC 9.6.7 | Verified in CI workflow |
| Optimization | -O2 | Set in release workflow build step |
| Linking | Dynamic (glibc) | Default GHC linking behavior |
| Obfuscation | None | Standard GHC compilation, no post-processing |
| Packing | None | Raw ELF binary, no UPX or equivalent |

### Integrity

| Property | Assertion | Evidence |
|----------|-----------|----------|
| Checksums | SHA-256 per artifact | Generated in release workflow |
| SBOM | CycloneDX JSON | Generated from cabal freeze file |
| Provenance | GitHub artifact attestation | `actions/attest-build-provenance` |
| Signing | Not currently implemented | See "Future Work" |

### Build Reproducibility

The build is **near-reproducible** given the same:
- GHC version (pinned in CI)
- Cabal index-state (pinned in cabal.project)
- Dependency versions (from freeze file)
- Runner image (ubuntu-latest at build time)

Full bit-for-bit reproducibility is not guaranteed because:
- ubuntu-latest changes over time
- GHC does not guarantee deterministic compilation across all conditions
- Timestamps may be embedded in some artifacts

## Non-Claims

We do **not** claim:
- Bit-for-bit reproducible builds
- Antivirus compatibility (static analysis tools may flag any binary)
- Perfect security (no software is perfectly secure)
- Absence of all possible bugs
- Suitability for any specific compliance framework without review

## Verification Instructions

### Verify Checksums

```bash
# Download the binary and checksum file
curl -LO https://github.com/jalsarraf0/Haskell-Orchestrator/releases/download/vX.Y.Z/orchestrator-X.Y.Z-linux-x86_64
curl -LO https://github.com/jalsarraf0/Haskell-Orchestrator/releases/download/vX.Y.Z/SHA256SUMS-X.Y.Z.txt

# Verify
sha256sum -c SHA256SUMS-X.Y.Z.txt
```

### Inspect SBOM

```bash
curl -LO https://github.com/jalsarraf0/Haskell-Orchestrator/releases/download/vX.Y.Z/sbom-X.Y.Z.json
python3 -m json.tool sbom-X.Y.Z.json
```

### Verify Build Provenance

```bash
gh attestation verify orchestrator-X.Y.Z-linux-x86_64 \
  --owner jalsarraf0
```

## Future Work

- GPG or Sigstore signing of release artifacts
- Fully reproducible builds via Nix or Docker
- Additional platform builds (macOS, Windows)
