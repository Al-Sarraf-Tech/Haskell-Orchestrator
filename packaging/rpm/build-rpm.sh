#!/usr/bin/env bash
set -euo pipefail
# Build .rpm package from pre-compiled binary
# Usage: build-rpm.sh <binary-path> <version>

BINARY="$1"
VERSION="$2"
TOPDIR="$(mktemp -d)"

trap 'rm -rf "$TOPDIR"' EXIT

mkdir -p "${TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy sources
cp "$BINARY" "${TOPDIR}/SOURCES/orchestrator"
cp README.md LICENSE CHANGELOG.md "${TOPDIR}/SOURCES/"

# Copy spec
cp packaging/rpm/haskell-orchestrator.spec "${TOPDIR}/SPECS/"

# Build
rpmbuild --define "_topdir ${TOPDIR}" \
         --define "version ${VERSION}" \
         -bb "${TOPDIR}/SPECS/haskell-orchestrator.spec"

# Copy result
find "${TOPDIR}/RPMS" -name "*.rpm" -exec cp {} . \;
echo "Built: $(ls ./*.rpm)"
