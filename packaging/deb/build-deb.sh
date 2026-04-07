#!/usr/bin/env bash
set -euo pipefail
# Build .deb package from pre-compiled binary
# Usage: build-deb.sh <binary-path> <version>

BINARY="$1"
VERSION="$2"
PKG="haskell-orchestrator"
ARCH="amd64"
WORKDIR="$(mktemp -d)"

trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "${WORKDIR}/DEBIAN"
mkdir -p "${WORKDIR}/usr/bin"
mkdir -p "${WORKDIR}/usr/share/doc/${PKG}"

# Control file
sed "s/VERSION_PLACEHOLDER/${VERSION}/" packaging/deb/control > "${WORKDIR}/DEBIAN/control"

# Binary
cp "$BINARY" "${WORKDIR}/usr/bin/orchestrator"
chmod 755 "${WORKDIR}/usr/bin/orchestrator"

# Docs
cp README.md LICENSE CHANGELOG.md "${WORKDIR}/usr/share/doc/${PKG}/"

# Build
dpkg-deb --build --root-owner-group "${WORKDIR}" "${PKG}_${VERSION}_${ARCH}.deb"
echo "Built: ${PKG}_${VERSION}_${ARCH}.deb"
