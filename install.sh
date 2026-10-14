#!/usr/bin/env bash
set -euo pipefail

REPO="mistralai/cli"
INSTALL_DIR="${MISTRAL_INSTALL_DIR:-$HOME/.mistral/bin}"
BUN_VERSION="1.4.0"

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

download() {
  curl -fsSL --retry 3 -o "$2" "$1"
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

MARKER_START="# >>> Mistral >>>"
MARKER_END="# <<< Mistral <<<"

shell_name() {
  local shell_path="${SHELL:-}"
  echo "${shell_path##*/}"
}

profile_for_shell() {
  case "$(shell_name)" in
    zsh)
      echo "${ZDOTDIR:-$HOME}/.zshrc"
      ;;
    bash)
      if [[ -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
      else
        echo "$HOME/.bash_profile"
      fi
      ;;
    fish)
      echo "$HOME/.config/fish/config.fish"
      ;;
    *)
      return 1
      ;;
  esac
}

path_line_for_shell() {
  case "$(shell_name)" in
    fish) echo "fish_add_path \"${INSTALL_DIR}\"" ;;
    *)    echo "export PATH=\"${INSTALL_DIR}:\$PATH\"" ;;
  esac
}

print_path_instructions() {
  warning "${INSTALL_DIR} is not on your PATH. Add it to your shell profile:"
  echo "  $1"
}

tty_available() {
  { : >/dev/tty; } 2>/dev/null
}

confirm() {
  local answer
  tty_available || return 1
  printf '%b' "${BLUE}[INPUT]${NC} $1 [Y/n] " >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    "" | [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

strip_paired_block() {
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    !holding && $0 == start { holding = 1; held = ""; next }
    holding && $0 == end { holding = 0; held = ""; next }
    holding { held = held == "" ? $0 : held "\n" $0; next }
    { print }
    END { if (holding && held != "") print held }
  ' "$1"
}

write_path_block() {
  local profile="$1" line="$2" rewritten
  mkdir -p "$(dirname "$profile")" || return 1
  touch "$profile" || return 1
  rewritten="$(mktemp)" || return 1

  if ! { strip_paired_block "$profile" >"$rewritten" &&
    printf '%s\n%s\n%s\n' "$MARKER_START" "$line" "$MARKER_END" >>"$rewritten"; }; then
    rm -f "$rewritten"
    return 1
  fi

  if ! cat "$rewritten" >"$profile"; then
    warning "${profile} may be incomplete; a complete copy is at ${rewritten}"
    return 1
  fi

  rm -f "$rewritten"
}

setup_path() {
  local profile line
  line="$(path_line_for_shell)"

  if [[ -n "${MISTRAL_NO_MODIFY_PATH:-}" ]]; then
    print_path_instructions "$line"
    return
  fi

  if ! profile="$(profile_for_shell)"; then
    print_path_instructions "$line"
    return
  fi

  if ! confirm "Add ${INSTALL_DIR} to your PATH in ${profile}?"; then
    print_path_instructions "$line"
    return
  fi

  if ! write_path_block "$profile" "$line"; then
    warning "Could not write to ${profile}."
    print_path_instructions "$line"
    return
  fi

  success "Added ${INSTALL_DIR} to your PATH in ${profile}"
  info "Restart your shell or run: source ${profile}"
}

print_bun_instructions() {
  warning "\`mistral apps\` needs bun. Install it with:"
  echo "  curl -fsSL https://bun.sh/install | bash -s \"bun-v${BUN_VERSION}\""
}

setup_bun() {
  local tmp="$1" bun_dir="${BUN_INSTALL:-$HOME/.bun}/bin"

  if command -v bun >/dev/null 2>&1; then
    return
  fi

  if [[ -x "$bun_dir/bun" ]]; then
    warning "bun is installed in ${bun_dir}, which is not on your PATH. Restart your shell or add it to your PATH."
    return
  fi

  if [[ "${MISTRAL_INSTALL_BUN:-}" == 0 ]]; then
    print_bun_instructions
    return
  fi

  if [[ "${MISTRAL_INSTALL_BUN:-}" != 1 ]] &&
    ! confirm "bun is not installed and \`mistral apps\` needs it. Install bun ${BUN_VERSION} from bun.sh?"; then
    print_bun_instructions
    return
  fi

  if ! download "https://bun.sh/install" "$tmp/bun-install.sh" ||
    ! bash "$tmp/bun-install.sh" "bun-v${BUN_VERSION}"; then
    warning "Could not install bun."
    print_bun_instructions
  fi
}

print_next_steps() {
  echo
  info "Next steps:"
  echo "  mistral login        Sign in through your browser"
  echo "  mistral context      Pick the organization and workspace to work in"
  echo "  mistral apps init    Scaffold your first app"
  echo
  echo "  mistral --help for everything else."
  print_completion_hint
}

print_completion_hint() {
  case "$(shell_name)" in
    bash)
      # Guarded eval so completions track CLI upgrades and a missing binary stays silent at shell start.
      echo "  Shell completions, add to ~/.bashrc:"
      echo "    command -v mistral >/dev/null && eval \"\$(mistral --completions bash)\""
      ;;
    zsh)
      echo "  Shell completions:"
      echo "    mkdir -p ~/.zsh/completions && mistral --completions zsh > ~/.zsh/completions/_mistral"
      echo "    # then in ~/.zshrc, before any compinit: fpath=(~/.zsh/completions \$fpath)"
      echo "    # if ~/.zshrc doesn't run compinit, add after fpath: autoload -Uz compinit && compinit"
      ;;
    fish)
      echo "  Shell completions:"
      echo "    mkdir -p ~/.config/fish/completions && mistral --completions fish > ~/.config/fish/completions/mistral.fish"
      ;;
    *)
      echo "  Shell completions: mistral --completions <bash|zsh|fish|sh>"
      ;;
  esac
}

main() {
  if [[ ! "${MISTRAL_INSTALL_BUN:-}" =~ ^[01]?$ ]]; then
    error "MISTRAL_INSTALL_BUN must be 0 or 1, got '${MISTRAL_INSTALL_BUN}'"
    exit 1
  fi

  local asset
  asset="$(detect_asset)"
  info "Detected platform asset: ${asset}"

  local version base
  version="${MISTRAL_VERSION:-}"
  if [[ -n "$version" ]]; then
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      error "MISTRAL_VERSION must be plain X.Y.Z, got '${version}'"
      exit 1
    fi
    base="https://github.com/${REPO}/releases/download/cli/v${version}"
    info "Downloading ${asset} v${version} from ${REPO}..."
  else
    base="https://github.com/${REPO}/releases/latest/download"
    info "Downloading latest ${asset} from ${REPO}..."
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf $(printf '%q' "$tmp")" EXIT

  if ! download "${base}/${asset}" "$tmp/$asset"; then
    error "Failed to download ${base}/${asset}"
    if [[ -n "$version" ]]; then
      error "Confirm release cli/v${version} exists: https://github.com/${REPO}/releases"
    fi
    exit 1
  fi

  if ! download "${base}/checksums.txt" "$tmp/checksums.txt"; then
    error "Failed to download ${base}/checksums.txt"
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
      setup_path
      ;;
  esac

  setup_bun "$tmp"
  print_next_steps
}

main "$@"
