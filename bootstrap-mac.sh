#!/usr/bin/env bash

set -euo pipefail

# Public bootstrap for macOS to prepare environment and run private dave-puter-ansible install.

require_macos() {
  if [[ "${OSTYPE:-}" != darwin* ]]; then
    echo "This bootstrap supports macOS only." >&2
    exit 1
  fi
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$('/opt/homebrew/bin/brew' shellenv)"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$('/usr/local/bin/brew' shellenv)"
  else
    echo "Homebrew installation did not expose brew on a known path." >&2
    exit 1
  fi
}

brew_install_if_missing() {
  local pkg="$1"
  if brew list --formula --versions "$pkg" >/dev/null 2>&1 || \
     brew list --cask --versions "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  if brew info --cask "$pkg" >/dev/null 2>&1; then
    brew install --cask "$pkg"
  else
    brew install "$pkg"
  fi
}

ensure_cli_tools() {
  brew update || true
  brew_install_if_missing git
  brew_install_if_missing gh
}

gh_auth_ensure() {
  if gh auth status >/dev/null 2>&1; then
    return 0
  fi
  echo "Logging into GitHub CLI (opens browser)..."
  gh auth login --hostname github.com --web --scopes repo || true
}

clone_or_update_gh_repo() {
  local gh_repo="$1"   # e.g., unlox775/dave-puter-ansible
  local dest_dir="$2"  # e.g., $HOME/mirrors/dave-puter-ansible
  if [[ -d "$dest_dir/.git" ]]; then
    git -C "$dest_dir" fetch --all --prune || true
    git -C "$dest_dir" pull --ff-only || true
  else
    gh repo clone "$gh_repo" "$dest_dir"
  fi
}

main() {
  require_macos
  ensure_homebrew
  ensure_cli_tools
  gh_auth_ensure

  local mirrors_dir="${MIRRORS_DIR:-$HOME/mirrors}"
  mkdir -p "$mirrors_dir"

  local ansible_dir="$mirrors_dir/dave-puter-ansible"
  clone_or_update_gh_repo "unlox775/dave-puter-ansible" "$ansible_dir"

  bash "$ansible_dir/install.sh"
}

main "$@"


