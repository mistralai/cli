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

# --- Uninstall (MISTRAL_UNINSTALL=1) ---
# Best effort and idempotent. This public script never names the internal
# build's binary or installer variables (see update-channel.ts); whatever else
# is left in the install directory is listed instead. Everything below runs
# under `set -euo pipefail` inherited from the top of the file, so every
# command that may legitimately fail sits in an `if` or behind `||`.

UNINSTALL_PATH_BLOCKS_REMOVED=0

# Paths are printed with %s so a backslash or % in them is never interpreted.
uninstall_info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$1"; }
uninstall_warn() { printf '%b[WARNING]%b %s\n' "$YELLOW" "$NC" "$1" >&2; }

# Like `confirm`, but the default is no: only y/yes answers it. Without a
# terminal, or when reading fails, the answer is no.
confirm_default_no() {
  local answer
  tty_available || return 1
  printf '%b[INPUT]%b %s [y/N] ' "$BLUE" "$NC" "$1" >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

uninstall_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Same precedence as the CLI: $MISTRAL_CONFIG_DIR, $XDG_CONFIG_HOME/mistral, ~/.config/mistral.
uninstall_config_dir() {
  local explicit xdg
  explicit="$(uninstall_trim "${MISTRAL_CONFIG_DIR:-}")"
  xdg="$(uninstall_trim "${XDG_CONFIG_HOME:-}")"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
  elif [[ -n "$xdg" ]]; then
    printf '%s\n' "$xdg/mistral"
  else
    printf '%s\n' "$HOME/.config/mistral"
  fi
}

# Succeeds for a canonical path that must never be deleted: /, $HOME, any
# directory containing $HOME, and $HOME/.mistral (logical and physical $HOME).
uninstall_is_protected_dir() {
  local canon="$1" home home_physical candidate
  home="$HOME"
  while [[ "$home" != "/" && "$home" == */ ]]; do home="${home%/}"; done
  home_physical="$(CDPATH='' cd -- "$home" 2>/dev/null && pwd -P)" || home_physical="$home"

  if [[ "$canon" == "/" ]]; then
    return 0
  fi
  for candidate in "$home" "$home_physical"; do
    if [[ "$canon" == "$candidate/.mistral" ]]; then
      return 0
    fi
    case "$candidate/" in
      "$canon"/*) return 0 ;;
    esac
  done
  return 1
}

# Every file the installer can write, not only the one for the current $SHELL:
# the shell or ZDOTDIR may differ from install time. One path per line.
uninstall_rc_files() {
  printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc"
  if [[ "${ZDOTDIR:-$HOME}" != "$HOME" ]]; then
    printf '%s\n' "$HOME/.zshrc"
  fi
  printf '%s\n' "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.config/fish/config.fish"
}

uninstall_sign_out() {
  local bin="$INSTALL_DIR/mistral"
  if [[ ! -f "$bin" || ! -x "$bin" ]]; then
    uninstall_warn "Skipping sign-out: no mistral binary at ${bin}. If you signed in, delete the mistral-cli keychain item by hand."
    return 0
  fi
  uninstall_info "Signing out (can take up to a minute offline)..."
  # </dev/null keeps the child from reading the rest of a piped script.
  if ! MISTRAL_DISABLE_UPDATE_CHECK=1 MISTRAL_DISABLE_FLAG_REFRESH=1 "$bin" logout </dev/null; then
    uninstall_warn "mistral logout failed; continuing. If you signed in, delete the mistral-cli keychain item by hand."
  fi
  return 0
}

uninstall_remove_file() {
  local file="$1"
  if [[ ! -e "$file" && ! -L "$file" ]]; then
    return 0
  fi
  if ! rm -f -- "$file"; then
    uninstall_warn "Could not remove ${file}"
    return 1
  fi
  uninstall_info "Removed ${file}"
  return 0
}

uninstall_strip_path_block() {
  local file="$1" rewritten status=0
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  grep -qxF "$MARKER_START" "$file" 2>/dev/null || status=$?
  if [[ "$status" == 1 ]]; then
    return 0
  fi
  if [[ "$status" != 0 ]]; then
    uninstall_warn "Could not read ${file}; remove the Mistral PATH block by hand."
    return 1
  fi
  # An explicit template: BSD mktemp ignores TMPDIR without one.
  if ! rewritten="$(mktemp "${TMPDIR:-/tmp}/mistral-rc.XXXXXX")"; then
    uninstall_warn "Could not create a temporary file to edit ${file}."
    return 1
  fi
  if ! strip_paired_block "$file" >"$rewritten"; then
    rm -f "$rewritten" || true
    uninstall_warn "Could not read ${file}; remove the Mistral PATH block by hand."
    return 1
  fi
  if ! cat "$rewritten" >"$file"; then
    uninstall_warn "${file} may be incomplete; a complete copy is at ${rewritten}"
    return 1
  fi
  rm -f "$rewritten" || true
  UNINSTALL_PATH_BLOCKS_REMOVED=1
  uninstall_info "Removed the Mistral PATH block from ${file}"
  return 0
}

# Returns 0 when the directory was removed or deliberately kept, 1 when removing failed.
uninstall_remove_config_dir() {
  local raw="${MISTRAL_CONFIG_DIR:-}" dir canon
  if [[ -n "$raw" && -z "$(uninstall_trim "$raw")" ]]; then
    uninstall_warn "MISTRAL_CONFIG_DIR is blank; not touching the config directory."
    return 0
  fi
  dir="$(uninstall_config_dir)"
  while [[ "$dir" != "/" && "$dir" == */ ]]; do dir="${dir%/}"; done

  if [[ -L "$dir" ]]; then
    uninstall_warn "${dir} is a symbolic link; not deleting it or what it points to."
    printf '  To drop only the link: rm -f %q\n' "$dir"
    return 0
  fi
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  if ! canon="$(CDPATH='' cd -- "$dir" 2>/dev/null && pwd -P)" || [[ -z "$canon" ]]; then
    uninstall_warn "Could not resolve ${dir}; not deleting it."
    return 1
  fi
  if uninstall_is_protected_dir "$canon"; then
    uninstall_warn "Refusing to delete ${canon}: it is, or contains, your home directory."
    return 0
  fi

  if confirm_default_no "Delete ${canon}? It holds your API key, feature-flag overrides and caches."; then
    if ! rm -rf -- "$canon"; then
      uninstall_warn "Could not fully remove ${canon}"
      return 1
    fi
    uninstall_info "Removed ${canon}"
    return 0
  fi
  uninstall_info "Kept ${canon}. Remove it with:"
  printf '  rm -rf %q\n' "$canon"
  return 0
}

# Lists, never deletes: other tools or your own data may depend on these.
uninstall_list_leftovers() {
  local bun_home="${BUN_INSTALL:-$HOME/.bun}" registry="$HOME/.mistral/registry"
  local file hits name containers="" volumes="" found=0

  while IFS= read -r file; do
    if [[ ! -f "$file" ]]; then
      continue
    fi
    if hits="$(grep -nF -e "$INSTALL_DIR" -e ".mistral/bin" -e "mistral --completions" -e "BUN_INSTALL" -e ".bun/" -e "$bun_home" "$file" 2>/dev/null)"; then
      if [[ "$found" == 0 ]]; then
        uninstall_info "Not removed (other tools or your data may use these):"
        found=1
      fi
      printf '  %s still has lines about mistral or bun (remove them by hand if unwanted):\n' "$file"
      printf '%s\n' "$hits" | sed 's/^/    /'
    fi
  done < <(uninstall_rc_files)

  if [[ -d "$registry" ]]; then
    if [[ "$found" == 0 ]]; then
      uninstall_info "Not removed (other tools or your data may use these):"
      found=1
    fi
    printf '  Pulled skills and prompts: %s\n' "$registry"
    printf '    rm -rf %q\n' "$registry"
  fi

  if [[ -d "$bun_home" ]]; then
    if [[ "$found" == 0 ]]; then
      uninstall_info "Not removed (other tools or your data may use these):"
      found=1
    fi
    printf '  bun (other tools may use it): %s\n' "$bun_home"
    printf '    rm -rf %q\n' "$bun_home"
  fi

  if command -v docker >/dev/null 2>&1; then
    containers="$(docker ps -a --filter 'name=^mistral-dev-' --format '{{.Names}}' </dev/null 2>/dev/null || true)"
    volumes="$(docker volume ls --filter 'name=^mistral-dev-' --format '{{.Name}}' </dev/null 2>/dev/null || true)"
  fi
  if [[ -n "$containers" || -n "$volumes" ]]; then
    if [[ "$found" == 0 ]]; then
      uninstall_info "Not removed (other tools or your data may use these):"
      found=1
    fi
    echo "  \`mistral apps dev\` Docker containers and volumes (the volumes hold your local database data):"
    if [[ -n "$containers" ]]; then
      while IFS= read -r name; do
        printf '    docker rm %q\n' "$name"
      done <<<"$containers"
    fi
    if [[ -n "$volumes" ]]; then
      while IFS= read -r name; do
        printf '    docker volume rm %q\n' "$name"
      done <<<"$volumes"
    fi
  fi
  return 0
}

uninstall() {
  local failed=0 file remaining

  if [[ "${MISTRAL_UNINSTALL}" != 1 ]]; then
    printf '%b[ERROR]%b MISTRAL_UNINSTALL must be 0 or 1, got '"'"'%s'"'"'\n' "$RED" "$NC" "$MISTRAL_UNINSTALL" >&2
    exit 1
  fi
  if [[ -z "$HOME" ]]; then
    error "HOME is empty; refusing to uninstall."
    exit 1
  fi

  uninstall_sign_out

  uninstall_remove_file "$INSTALL_DIR/mistral" || failed=1
  if [[ "$INSTALL_DIR" == "$HOME/.mistral/bin" ]]; then
    if rmdir "$INSTALL_DIR" 2>/dev/null; then
      rmdir "$HOME/.mistral" 2>/dev/null || true
    fi
  fi

  while IFS= read -r file; do
    uninstall_strip_path_block "$file" || failed=1
  done < <(uninstall_rc_files)

  for file in "$HOME/.zsh/completions/_mistral" "$HOME/.config/fish/completions/mistral.fish"; do
    uninstall_remove_file "$file" || failed=1
  done

  uninstall_remove_config_dir || failed=1

  remaining="$(ls -A "$INSTALL_DIR" 2>/dev/null || true)"
  if [[ -n "$remaining" ]]; then
    if [[ "$UNINSTALL_PATH_BLOCKS_REMOVED" == 1 ]]; then
      uninstall_info "PATH block removed; entries below are no longer on PATH."
    fi
    uninstall_info "Left in ${INSTALL_DIR}:"
    printf '%s\n' "$remaining" | sed 's/^/  /'
  fi
  uninstall_list_leftovers

  if [[ "$failed" == 1 ]]; then
    error "Uninstall finished with errors."
    exit 1
  fi
  success "mistral is uninstalled. Open a new shell to drop it from your PATH."
  return 0
}

main() {
  if [[ -n "${MISTRAL_UNINSTALL:-}" && "${MISTRAL_UNINSTALL}" != 0 ]]; then
    uninstall
    return
  fi

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
