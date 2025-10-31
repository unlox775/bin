#!/usr/bin/env bash

set -euo pipefail

# Thin installer: fetch only tech_tools/dot_portahome from brain-graft via sparse-checkout,
# run its installer to provision ~/.portahome (including bin), and leave the clone
# ready to expand later into the full repository.

REPO_SLUG="unlox775/brain-graft"
DEST_DIR="${HOME}/mirrors/brain-graft"
SPARSE_PATH="tech_tools/dot_portahome"

log() { printf "[thin-portahome] %s\n" "$*"; }
warn() { printf "[thin-portahome] WARN: %s\n" "$*" >&2; }
die() { printf "[thin-portahome] ERROR: %s\n" "$*" >&2; exit 1; }

ensure_git() {
  if command -v git >/dev/null 2>&1; then return 0; fi
  if command -v brew >/dev/null 2>&1; then
    log "Installing git via Homebrew..."
    brew install git || true
  fi
  command -v git >/dev/null 2>&1 || die "git is required. Please install git and re-run."
}

ensure_gh() {
  if command -v gh >/dev/null 2>&1; then return 0; fi
  if command -v brew >/dev/null 2>&1; then
    log "Installing GitHub CLI (gh) via Homebrew..."
    brew install gh || true
  fi
  command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required. Please install gh and re-run."
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then return 0; fi
  log "Logging into GitHub (opens browser)..."
  gh auth login --hostname github.com --web --scopes repo || die "GitHub authentication failed."
}

clone_or_prepare_repo() {
  mkdir -p "${DEST_DIR}"
  if [[ -d "${DEST_DIR}/.git" ]]; then
    log "Existing clone detected at ${DEST_DIR}. Updating..."
    git -C "${DEST_DIR}" remote set-url origin "https://github.com/${REPO_SLUG}.git" || true
    git -C "${DEST_DIR}" fetch --all --prune --depth=1 || true
  else
    log "Cloning ${REPO_SLUG} (no checkout)..."
    gh repo clone "${REPO_SLUG}" "${DEST_DIR}" -- --no-checkout
  fi
}

configure_sparse_checkout() {
  log "Configuring sparse-checkout for ${SPARSE_PATH}..."
  pushd "${DEST_DIR}" >/dev/null
  default_branch="$(gh repo view "${REPO_SLUG}" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)"
  git sparse-checkout init --cone || true
  git sparse-checkout set "${SPARSE_PATH}"
  if ! git checkout -B "${default_branch}" "origin/${default_branch}" 2>/dev/null; then
    git checkout "${default_branch}" || git checkout -t "origin/${default_branch}" || true
  fi
  popd >/dev/null
}

run_portahome_installer() {
  local installer="${DEST_DIR}/${SPARSE_PATH}/install"
  if [[ ! -f "${installer}" ]]; then
    die "dot_portahome installer not found at ${installer}"
  fi
  log "Running dot_portahome installer..."
  chmod +x "${installer}" || true
  "${installer}"
}

post_instructions() {
  cat <<EOF

Next steps:
- To expand this sparse checkout into the full repo later:
    cd "${DEST_DIR}" \
    && git sparse-checkout disable \
    && git pull --ff-only --prune

- Your ~/.portahome should now be installed (including bin if provided by the installer).
  Add its bin to PATH if not already added by the installer, e.g.:
    echo 'export PATH="$HOME/.portahome/bin:\$PATH"' >> ~/.zshrc

EOF
}

main() {
  ensure_git
  ensure_gh
  ensure_gh_auth
  clone_or_prepare_repo
  configure_sparse_checkout
  run_portahome_installer
  post_instructions
  log "Thin port-a-home setup complete."
}

main "$@"


