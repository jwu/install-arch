#!/bin/bash
set -uo pipefail

# ==========================================
# install-arch
# ==========================================

# One entry point for a bare Arch Linux machine: clone or update the config
# repos under ~/bin, then run their installers in order.
#
# Every step is best-effort. On a bare machine the network and the toolchain
# are the least predictable parts -- the waybar niri-windows module is fetched
# from GitHub and compiled from source -- and a single failed build must not
# skip the config sync that comes after it. Failures are recorded, the run
# continues, and the summary at the end names what is missing while the exit
# code stays non-zero.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/bin}"

# Repos this script drives, in install order. configs comes first because its
# installer also syncs the Fcitx5/Rime config from desktop-settings, and
# pi-config is deployed last because it depends on the pi CLI.
REPOS=(configs desktop-settings pi-config)
CONFIG_REPO="configs"
PI_REPO="pi-config"

GIT_SSH_BASE="${GIT_SSH_BASE:-git@github.com:jwu}"
GIT_HTTPS_BASE="${GIT_HTTPS_BASE:-https://github.com/jwu}"

FAILED_STEPS=()

# ==========================================
# Step runner
# ==========================================

step() {
  local name="$1"
  shift
  local rc=0
  echo ""
  echo ">>> $name"
  "$@" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "    ok"
  else
    FAILED_STEPS+=("$name")
    echo "    FAILED (exit $rc); continuing" >&2
  fi
}

summary() {
  echo ""
  echo "=========================================="
  if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
    echo ">>> All steps completed."
    return 0
  fi
  echo ">>> Finished with ${#FAILED_STEPS[@]} failed step(s):"
  local s
  for s in "${FAILED_STEPS[@]}"; do
    echo "      - $s"
  done
  echo ""
  echo "    These pieces are missing or stale. Re-run this script after fixing"
  echo "    them; it is idempotent and only redoes what is out of date."
  return 1
}

echo ">>> install-arch"
echo "    Source dir: $SCRIPT_DIR"
echo "    Repos dir:  $BIN_DIR"

# ==========================================
# Hard prerequisites: without these nothing below can run.
# ==========================================

if ! command -v pacman &> /dev/null; then
  echo "Error: pacman is not available. This installer targets Arch Linux."
  exit 1
fi

for tool in git curl sudo; do
  if ! command -v "$tool" &> /dev/null; then
    echo "Error: $tool is required but not installed."
    exit 1
  fi
done

# ==========================================
# Repositories
# ==========================================

# Existing checkouts are kept and only refreshed: these repos are also edited
# by hand, so a dirty tree or a local commit is normal and must not fail the
# install. A pull that cannot fast-forward is therefore reported and ignored.
ensure_repo() {
  local name="$1"
  local dest="$BIN_DIR/$name"

  if [ -e "$dest" ] && [ ! -d "$dest/.git" ]; then
    echo "    $dest exists but is not a git checkout" >&2
    return 1
  fi

  if [ -d "$dest/.git" ]; then
    echo "    $name: updating (git pull --ff-only)"
    git -C "$dest" pull --ff-only || echo "    $name: pull skipped (local changes or no network)"
    return 0
  fi

  echo "    $name: cloning into $dest"
  if git clone "$GIT_SSH_BASE/$name.git" "$dest" 2>/dev/null; then
    return 0
  fi
  echo "    $name: SSH clone failed, retrying over HTTPS"
  git clone "$GIT_HTTPS_BASE/$name.git" "$dest" || return 1
}

# ==========================================
# pi CLI: pi-config deploys ~/.pi/agent for it, but configs does not install it.
# ==========================================

ensure_pi() {
  if command -v pi &> /dev/null; then
    echo "    pi: $(command -v pi)"
    return 0
  fi
  if ! command -v npm &> /dev/null; then
    echo "    pi is not installed and npm is unavailable; install @earendil-works/pi-coding-agent manually" >&2
    return 1
  fi
  echo "    pi: installing @earendil-works/pi-coding-agent (npm -g)"
  npm install -g @earendil-works/pi-coding-agent || return 1
}

# ==========================================
# Repo installers
# ==========================================

# Packages, Oh My Zsh, the waybar module, gpu-watch and the config sync.
run_configs() {
  bash "$BIN_DIR/$CONFIG_REPO/linux/install.sh"
}

# Deploy the pi resources to ~/.pi/agent.
run_pi_config() {
  bash "$BIN_DIR/$PI_REPO/install.sh"
}

# ==========================================
# Run
# ==========================================

mkdir -p "$BIN_DIR"

for repo in "${REPOS[@]}"; do
  step "repository: $repo" ensure_repo "$repo"
done

step "configs: packages, waybar module, config sync" run_configs
step "pi CLI (prerequisite for pi-config)" ensure_pi
step "pi-config: deploy ~/.pi/agent" run_pi_config

summary
