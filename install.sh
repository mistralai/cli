#!/usr/bin/env bash
set -euo pipefail

REPO="mistralai/cli"
INSTALL_DIR="${MISTRAL_INSTALL_DIR:-$HOME/.mistral/bin}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    return 1
  fi
}

detect_asset() {
  local os arch
  case "$(uname -s)" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    *) error "Unsupported operating system: $(uname -s)"; exit 1 ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch="arm64" ;;
    x86_64 | amd64)  arch="x64" ;;
    *) error "Unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
  echo "mistral-${os}-${arch}"
}

main() {
  if ! command -v gh >/dev/null 2>&1; then
    error "GitHub CLI (gh) is required. Install from https://cli.github.com then run 'gh auth login'."
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    error "GitHub CLI is not authenticated. Run 'gh auth login' with an account that has access to ${REPO}."
    exit 1
  fi

  local asset
  asset="$(detect_asset)"
  info "Detected platform asset: ${asset}"

  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf $(printf '%q' "$tmp")" EXIT

  info "Downloading latest ${asset} from ${REPO}..."
  if ! gh release download \
    --repo "$REPO" \
    --pattern "$asset" \
    --pattern "checksums.txt" \
    --dir "$tmp" \
    --clobber; then
    error "Failed to download from ${REPO}. Confirm your gh account has access to ${REPO}."
    exit 1
  fi

  if [[ ! -f "$tmp/$asset" ]]; then
    error "Downloaded asset not found: ${asset}"
    exit 1
  fi

  if [[ ! -f "$tmp/checksums.txt" ]]; then
    error "checksums.txt not found in release"
    exit 1
  fi

  local expected actual
  expected="$(awk -v f="$asset" '{sub(/^\*/,"",$2)} $2==f {print $1}' "$tmp/checksums.txt")"
  if [[ -z "$expected" ]]; then
    error "No checksum entry for ${asset} in checksums.txt"
    exit 1
  fi
  actual="$(sha256_of "$tmp/$asset")" || { error "SHA-256 computation failed"; exit 1; }
  if [[ "$actual" != "$expected" ]]; then
    error "Checksum mismatch for ${asset}"
    error "  expected: $expected"
    error "  actual:   $actual"
    exit 1
  fi
  success "Checksum verified"

  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$tmp/$asset" "$INSTALL_DIR/mistral"
  success "Installed mistral to ${INSTALL_DIR}/mistral"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*)
      success "mistral is on your PATH: $("$INSTALL_DIR/mistral" --version)"
      ;;
    *)
      warning "${INSTALL_DIR} is not on your PATH. Add it to your shell profile:"
      echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
      ;;
  esac
}

main "$@"
