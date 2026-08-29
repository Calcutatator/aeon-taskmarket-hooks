#!/usr/bin/env bash
# Build a disposable, commit-pinned TaskMarket hook workspace for this skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TPL="$SKILL_DIR/templates"
TMP_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
DIR="${TASKMARKET_HOOKBUILD_DIR:-$TMP_BASE/aeon-taskmarket-hookbuild}"
TOOLS_DIR="${TASKMARKET_FOUNDRY_DIR:-$TMP_BASE/aeon-taskmarket-foundry-v1.7.1}"

FOUNDRY_VERSION="1.7.1"
TASKMARKET_PIN="a85cc8dae76e0fc6da9e463375fd2e385710d442"
OPENZEPPELIN_PIN="fcbae5394ae8ad52d8e580a3477db99814b9d565"
OPENZEPPELIN_UPGRADEABLE_PIN="7bf4727aacdbfaa0f36cbd664654d0c9e1dc52bf"
FORGE_STD_PIN="1801b0541f4fda118a10798fd3486bb7051c5dd6"

log() { echo "stage-deploy-taskmarket-hook: $*" >&2; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    log "SHA-256 utility unavailable"
    return 1
  fi
}

dependency_tree_sha256() {
  local listing
  listing="$(mktemp)" || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    find lib -type f -exec sha256sum {} + | LC_ALL=C sort > "$listing" || { rm -f "$listing"; return 1; }
    sha256sum "$listing" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    find lib -type f -exec shasum -a 256 {} + | LC_ALL=C sort > "$listing" || { rm -f "$listing"; return 1; }
    shasum -a 256 "$listing" | awk '{print $1}'
  else
    rm -f "$listing"
    return 1
  fi
  rm -f "$listing"
}

resolve_dedicated_dir() {
  local candidate="$1" allowed_one="$2" allowed_two="$3" parent resolved
  [ -n "$candidate" ] && [ "$candidate" != "/" ] && [ "$candidate" != "." ] \
    || { log "REFUSE unsafe directory: $candidate"; return 1; }
  if [ -e "$candidate" ]; then
    resolved="$(cd "$candidate" && pwd -P)" || return 1
  else
    parent="$(cd "$(dirname "$candidate")" && pwd -P)" || return 1
    resolved="$parent/$(basename "$candidate")"
  fi
  [ "${#resolved}" -ge 12 ] || { log "REFUSE suspiciously broad directory: $resolved"; return 1; }
  case "$(basename "$resolved")" in
    "$allowed_one"|"$allowed_two") ;;
    *) log "REFUSE non-dedicated directory name: $resolved"; return 1 ;;
  esac
  printf '%s\n' "$resolved"
}

install_pinned_foundry() {
  local os arch asset expected archive observed tmp_dir
  if command -v forge >/dev/null 2>&1 && forge --version 2>/dev/null | head -1 | grep -q "Version: $FOUNDRY_VERSION"; then
    dirname "$(command -v forge)"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || { log "curl is required to install pinned Foundry"; return 1; }
  command -v tar >/dev/null 2>&1 || { log "tar is required to install pinned Foundry"; return 1; }
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)
      asset="foundry_v${FOUNDRY_VERSION}_linux_amd64.tar.gz"
      expected="cf7e688ed0c4c48adffca788b496076e31060b67ac5afe1e43dbb5499c20c88b"
      ;;
    Linux/aarch64|Linux/arm64)
      asset="foundry_v${FOUNDRY_VERSION}_linux_arm64.tar.gz"
      expected="c8fe8fa09ae3aba2c81b510c6f9da3a9d468029b9580e690b245b3f0aea687ae"
      ;;
    Darwin/x86_64)
      asset="foundry_v${FOUNDRY_VERSION}_darwin_amd64.tar.gz"
      expected="c7fd1f5c9bf718d30b5cb6fc94eac605039de2aa50afc4c545a4dddc1e411acb"
      ;;
    Darwin/arm64)
      asset="foundry_v${FOUNDRY_VERSION}_darwin_arm64.tar.gz"
      expected="eacdc67718fac857cad9e19c7f6729dd80de731d09df81856391d093cfcab547"
      ;;
    *) log "unsupported Foundry platform: $os/$arch"; return 1 ;;
  esac

  tmp_dir="$(mktemp -d "${TMP_BASE%/}/aeon-foundry-download.XXXXXX")"
  archive="$tmp_dir/$asset"
  log "downloading Foundry v$FOUNDRY_VERSION ($os/$arch)"
  if ! curl --fail --location --silent --show-error --retry 2 \
    "https://github.com/foundry-rs/foundry/releases/download/v${FOUNDRY_VERSION}/${asset}" \
    --output "$archive"; then
    rm -rf -- "$tmp_dir"
    return 1
  fi
  observed="$(sha256_file "$archive")" || { rm -rf -- "$tmp_dir"; return 1; }
  [ "$observed" = "$expected" ] || {
    log "Foundry archive checksum mismatch: expected=$expected observed=$observed"
    rm -rf -- "$tmp_dir"
    return 1
  }
  rm -rf -- "$TOOLS_DIR"
  mkdir -p "$TOOLS_DIR/bin"
  tar -xzf "$archive" -C "$TOOLS_DIR/bin"
  rm -rf -- "$tmp_dir"
  [ -x "$TOOLS_DIR/bin/forge" ] && [ -x "$TOOLS_DIR/bin/cast" ] \
    || { log "pinned Foundry archive was incomplete"; return 1; }
  printf '%s\n' "$TOOLS_DIR/bin"
}

DIR="$(resolve_dedicated_dir "$DIR" taskmarket-hookbuild aeon-taskmarket-hookbuild)"
TOOLS_DIR="$(resolve_dedicated_dir "$TOOLS_DIR" taskmarket-foundry-v1.7.1 aeon-taskmarket-foundry-v1.7.1)"
FOUNDRY_BIN="$(install_pinned_foundry)" || { log "could not provision pinned Foundry"; exit 3; }
export PATH="$FOUNDRY_BIN:$PATH"
log "$(forge --version 2>/dev/null | head -1)"

command -v git >/dev/null 2>&1 || { log "git is required"; exit 3; }
rm -rf -- "$DIR"
mkdir -p "$DIR/src" "$DIR/test" "$DIR/script" "$DIR/lib"
cd "$DIR"

# These are the exact dependency revisions shipped by create-taskmarket-hook@0.1.0.
forge install --no-git "daydreamsai/taskmarket-contracts@$TASKMARKET_PIN"
forge install --no-git "OpenZeppelin/openzeppelin-contracts@$OPENZEPPELIN_PIN"
forge install --no-git "OpenZeppelin/openzeppelin-contracts-upgradeable@$OPENZEPPELIN_UPGRADEABLE_PIN"
forge install --no-git "foundry-rs/forge-std@$FORGE_STD_PIN"

cp "$TPL/foundry.toml" "$TPL/remappings.txt" .
cp "$TPL/Hook.sol" src/
cp "$TPL/DeployHook.s.sol" script/
cp "$TPL/HookBehavior.t.sol" "$TPL/HookFixture.sol" "$TPL/HookLifecycle.t.sol" \
  "$TPL/HookDiamondLifecycle.t.sol" "$TPL/HookFork.t.sol" test/
cp "$TPL/chains.tsv" taskmarket-chains.tsv
printf '%s\n' "$TASKMARKET_PIN" > taskmarket.commit
printf '%s\n' "$FOUNDRY_BIN" > foundry-bin.path

DEP_TREE_SHA256="$(dependency_tree_sha256)"
printf '%s\n' "$DEP_TREE_SHA256" > taskmarket-dependency-tree.sha256

forge build
[ -n "${GITHUB_PATH:-}" ] && printf '%s\n' "$FOUNDRY_BIN" >> "$GITHUB_PATH"
[ -n "${GITHUB_ENV:-}" ] && {
  printf 'TASKMARKET_HOOKBUILD_DIR=%s\n' "$DIR" >> "$GITHUB_ENV"
  printf 'TASKMARKET_DEPENDENCY_TREE_SHA256=%s\n' "$DEP_TREE_SHA256" >> "$GITHUB_ENV"
}
log "pinned project built at $DIR"
log "dependency tree locked: $DEP_TREE_SHA256"
