#!/usr/bin/env bash
set -euo pipefail

# Haskell Orchestrator — Official Installer
# Builds from source, installs binary, and garbage-collects old artifacts.

PRODUCT="orchestrator"
VERSION="4.0.0"
DEFAULT_INSTALLDIR="$HOME/.local/bin"
CABAL_STORE="${CABAL_DIR:-$HOME/.cabal}/store"

# --- Colours (if terminal) ---
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; RESET=''
fi

info()  { printf "${GREEN}[install]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[install]${RESET} %s\n" "$*"; }
error() { printf "${RED}[install]${RESET} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --installdir DIR   Install binary to DIR (default: $DEFAULT_INSTALLDIR)
  --no-gc            Skip garbage collection of old store entries
  --gc-only          Only run garbage collection, don't build or install
  --system           Install to /usr/local/bin (requires sudo)
  --clean            Clean build artifacts before building
  -O2                Build with full optimizations (slower build, faster binary)
  -h, --help         Show this help
EOF
}

# --- Parse arguments ---
INSTALLDIR="$DEFAULT_INSTALLDIR"
DO_GC=true
GC_ONLY=false
CLEAN_BUILD=false
OPT_LEVEL="-O1"
USE_SUDO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --installdir)  INSTALLDIR="$2"; shift 2 ;;
    --no-gc)       DO_GC=false; shift ;;
    --gc-only)     GC_ONLY=true; shift ;;
    --system)      INSTALLDIR="/usr/local/bin"; USE_SUDO="sudo"; shift ;;
    --clean)       CLEAN_BUILD=true; shift ;;
    -O2)           OPT_LEVEL="-O2"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown option: $1" ;;
  esac
done

# --- Prerequisites ---
check_prereqs() {
  for cmd in ghc cabal; do
    command -v "$cmd" &>/dev/null || die "$cmd not found — install GHCup first: https://www.haskell.org/ghcup/"
  done
  local ghc_ver
  ghc_ver=$(ghc --numeric-version)
  info "GHC $ghc_ver, $(cabal --version | head -1)"
}

# --- Garbage collection ---
gc_store() {
  info "Garbage-collecting old Cabal store entries..."

  local gc_count=0
  local gc_bytes=0

  # Find the GHC-versioned store directory
  local ghc_ver
  ghc_ver=$(ghc --numeric-version)
  local store_dir="${CABAL_STORE}/ghc-${ghc_ver}"

  if [ ! -d "$store_dir" ]; then
    info "No Cabal store found at $store_dir — nothing to collect"
    return
  fi

  # Remove old orchestrator-related packages (keep only current version)
  local pkg_patterns=(
    "orchestrator-[0-9]*"
    "orchestrator-business-[0-9]*"
    "orchestrator-enterprise-[0-9]*"
    "haskell-ci-orchestrator-[0-9]*"
  )

  for pattern in "${pkg_patterns[@]}"; do
    while IFS= read -r -d '' entry; do
      local base
      base=$(basename "$entry")
      # Keep entries matching the current version
      if [[ "$base" == *"-${VERSION}-"* ]]; then
        continue
      fi
      local size
      size=$(du -sb "$entry" 2>/dev/null | cut -f1 || echo 0)
      gc_bytes=$((gc_bytes + size))
      gc_count=$((gc_count + 1))
      rm -rf "$entry"
    done < <(find "$store_dir" -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null)
  done

  # Clean stale package.db entries
  local pkg_db="$store_dir/package.db"
  if [ -d "$pkg_db" ]; then
    for pattern in "${pkg_patterns[@]}"; do
      while IFS= read -r -d '' conf; do
        local base
        base=$(basename "$conf")
        if [[ "$base" == *"-${VERSION}-"* ]]; then
          continue
        fi
        rm -f "$conf"
        gc_count=$((gc_count + 1))
      done < <(find "$pkg_db" -maxdepth 1 -name "${pattern}*.conf" -print0 2>/dev/null)
    done

    # Recache the package database
    if command -v ghc-pkg &>/dev/null; then
      ghc-pkg --package-db="$pkg_db" recache 2>/dev/null || true
    fi
  fi

  # Clean stale dist-newstyle cache
  if [ -d "dist-newstyle/cache" ]; then
    rm -rf dist-newstyle/cache
    info "Cleared dist-newstyle cache"
  fi

  local gc_mb=$(( gc_bytes / 1048576 ))
  if [ "$gc_count" -gt 0 ]; then
    info "Collected $gc_count stale entries (~${gc_mb} MB freed)"
  else
    info "No stale entries found — store is clean"
  fi
}

# --- Build ---
build() {
  if [ "$CLEAN_BUILD" = true ]; then
    info "Cleaning build artifacts..."
    rm -rf dist-newstyle
  fi

  info "Updating package index..."
  cabal update 2>&1 | tail -1

  info "Building $PRODUCT $VERSION ($OPT_LEVEL)..."
  cabal build exe:orchestrator "$OPT_LEVEL" 2>&1 | grep -E '^(Building|Compiling|Linking|Completed)' || true

  info "Running tests..."
  if cabal test all --test-show-details=direct 2>&1 | tail -5; then
    info "All tests passed"
  else
    warn "Some tests failed — binary will still be installed"
  fi
}

# --- Install ---
install_bin() {
  info "Installing $PRODUCT to $INSTALLDIR..."
  $USE_SUDO mkdir -p "$INSTALLDIR"
  cabal install exe:orchestrator "$OPT_LEVEL" \
    --install-method=copy \
    --overwrite-policy=always \
    --installdir="$INSTALLDIR" 2>&1 | grep -v '^Wrote\|^Resolving\|^Build profile' || true

  # Verify
  local installed="$INSTALLDIR/$PRODUCT"
  if [ -x "$installed" ]; then
    local ver_line
    ver_line=$("$installed" --help 2>&1 | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    info "Installed: $installed ($ver_line)"
  else
    die "Installation failed — $installed not found or not executable"
  fi

  # Check PATH
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALLDIR"; then
    warn "$INSTALLDIR is not in PATH — add it:"
    warn "  echo 'export PATH=\"$INSTALLDIR:\$PATH\"' >> ~/.bashrc"
  fi
}

# --- Main ---
main() {
  printf "${BOLD}Haskell Orchestrator Installer${RESET}\n"
  printf "Version: %s\n\n" "$VERSION"

  check_prereqs

  if [ "$GC_ONLY" = true ]; then
    gc_store
    exit 0
  fi

  build
  install_bin

  if [ "$DO_GC" = true ]; then
    gc_store
  fi

  printf "\n${GREEN}Installation complete.${RESET}\n"
  printf "Run: ${BOLD}orchestrator demo${RESET} to get started\n"
  printf "Run: ${BOLD}orchestrator ui${RESET}   to launch the web dashboard\n"
}

main
