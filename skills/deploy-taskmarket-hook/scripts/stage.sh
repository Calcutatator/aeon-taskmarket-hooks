#!/usr/bin/env bash
# Build a fresh, commit-pinned TaskMarket hook workspace for this skill.
# This script never deletes a directory. Every default build is a new mktemp path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
TPL="$SKILL_DIR/templates"
TMP_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
STATE_FILE="${TASKMARKET_HOOKBUILD_STATE_FILE:-$TMP_BASE/aeon-taskmarket-hookbuild.active}"

FOUNDRY_VERSION="1.7.1"
TASKMARKET_PIN="a85cc8dae76e0fc6da9e463375fd2e385710d442"
OPENZEPPELIN_PIN="fcbae5394ae8ad52d8e580a3477db99814b9d565"
OPENZEPPELIN_UPGRADEABLE_PIN="7bf4727aacdbfaa0f36cbd664654d0c9e1dc52bf"
FORGE_STD_PIN="1801b0541f4fda118a10798fd3486bb7051c5dd6"
BUILD_SENTINEL="aeon-taskmarket-hooks:1.0.0"

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

resolve_fresh_build_dir() {
  local candidate parent resolved
  if [ -z "${TASKMARKET_HOOKBUILD_DIR:-}" ]; then
    mktemp -d "$TMP_BASE/aeon-taskmarket-hookbuild.XXXXXX"
    return
  fi
  candidate="$TASKMARKET_HOOKBUILD_DIR"
  [ -n "$candidate" ] && [ "$candidate" != "/" ] && [ "$candidate" != "." ] \
    || { log "REFUSE unsafe TASKMARKET_HOOKBUILD_DIR=$candidate"; return 1; }
  [ ! -e "$candidate" ] || { log "REFUSE existing build directory; provide a fresh path: $candidate"; return 1; }
  parent="$(cd "$(dirname "$candidate")" && pwd -P)" || return 1
  resolved="$parent/$(basename "$candidate")"
  [ "${#resolved}" -ge 12 ] || { log "REFUSE suspiciously broad build path: $resolved"; return 1; }
  case "$(basename "$resolved")" in
    taskmarket-hookbuild|aeon-taskmarket-hookbuild) ;;
    *) log "REFUSE non-dedicated build directory name: $resolved"; return 1 ;;
  esac
  mkdir "$resolved"
  printf '%s\n' "$resolved"
}

resolve_foundry_asset() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os/$arch" in
    Linux/x86_64)
      printf '%s\t%s\n' "foundry_v${FOUNDRY_VERSION}_linux_amd64.tar.gz" "cf7e688ed0c4c48adffca788b496076e31060b67ac5afe1e43dbb5499c20c88b"
      ;;
    Linux/aarch64|Linux/arm64)
      printf '%s\t%s\n' "foundry_v${FOUNDRY_VERSION}_linux_arm64.tar.gz" "c8fe8fa09ae3aba2c81b510c6f9da3a9d468029b9580e690b245b3f0aea687ae"
      ;;
    Darwin/x86_64)
      printf '%s\t%s\n' "foundry_v${FOUNDRY_VERSION}_darwin_amd64.tar.gz" "c7fd1f5c9bf718d30b5cb6fc94eac605039de2aa50afc4c545a4dddc1e411acb"
      ;;
    Darwin/arm64)
      printf '%s\t%s\n' "foundry_v${FOUNDRY_VERSION}_darwin_arm64.tar.gz" "eacdc67718fac857cad9e19c7f6729dd80de731d09df81856391d093cfcab547"
      ;;
    *) log "unsupported Foundry platform: $os/$arch"; return 1 ;;
  esac
}

command -v curl >/dev/null 2>&1 || { log "curl is required"; exit 3; }
command -v tar >/dev/null 2>&1 || { log "tar is required"; exit 3; }
command -v git >/dev/null 2>&1 || { log "git is required"; exit 3; }

DIR="$(resolve_fresh_build_dir)"
TOOLS_DIR="$DIR/toolchain"
FOUNDRY_BIN="$TOOLS_DIR/stage-bin"
ARCHIVE="$TOOLS_DIR/foundry-v${FOUNDRY_VERSION}.tar.gz"
mkdir -p "$DIR/src" "$DIR/test" "$DIR/script" "$DIR/lib" "$FOUNDRY_BIN"

IFS=$'\t' read -r FOUNDRY_ASSET FOUNDRY_ARCHIVE_SHA256 <<<"$(resolve_foundry_asset)"
log "downloading Foundry v$FOUNDRY_VERSION ($FOUNDRY_ASSET)"
curl --fail --location --silent --show-error --retry 2 \
  "https://github.com/foundry-rs/foundry/releases/download/v${FOUNDRY_VERSION}/${FOUNDRY_ASSET}" \
  --output "$ARCHIVE"
OBSERVED_ARCHIVE_SHA256="$(sha256_file "$ARCHIVE")"
[ "$OBSERVED_ARCHIVE_SHA256" = "$FOUNDRY_ARCHIVE_SHA256" ] || {
  log "Foundry archive checksum mismatch: expected=$FOUNDRY_ARCHIVE_SHA256 observed=$OBSERVED_ARCHIVE_SHA256"
  exit 3
}
tar -xzf "$ARCHIVE" -C "$FOUNDRY_BIN"
[ -x "$FOUNDRY_BIN/forge" ] && [ -x "$FOUNDRY_BIN/cast" ] \
  || { log "pinned Foundry archive was incomplete"; exit 3; }
export PATH="$FOUNDRY_BIN:$PATH"
log "$(forge --version 2>/dev/null | head -1)"

cd "$DIR"
forge install --no-git "daydreamsai/taskmarket-contracts@$TASKMARKET_PIN"
forge install --no-git "OpenZeppelin/openzeppelin-contracts@$OPENZEPPELIN_PIN"
forge install --no-git "OpenZeppelin/openzeppelin-contracts-upgradeable@$OPENZEPPELIN_UPGRADEABLE_PIN"
forge install --no-git "foundry-rs/forge-std@$FORGE_STD_PIN"

cp "$TPL/foundry.toml" "$TPL/remappings.txt" .
cp "$TPL/Hook.sol" src/
cp "$TPL/DeployHook.s.sol" "$TPL/BroadcastHook.s.sol" script/
cp "$TPL/HookBehavior.t.sol" "$TPL/HookFixture.sol" "$TPL/HookLifecycle.t.sol" \
  "$TPL/HookDiamondLifecycle.t.sol" "$TPL/HookFork.t.sol" test/
cp "$TPL/chains.tsv" taskmarket-chains.tsv
cp "$TPL/hook-manifest.template.json" hook-manifest.template.json
printf '%s\n' "$TASKMARKET_PIN" > taskmarket.commit
printf '%s\n' "$BUILD_SENTINEL" > .aeon-taskmarket-hookbuild
printf '%s\n' "$FOUNDRY_VERSION" > toolchain/foundry.version
printf '%s\n' "$FOUNDRY_ASSET" > toolchain/foundry.asset
printf '%s\n' "$FOUNDRY_ARCHIVE_SHA256" > toolchain/foundry-archive.sha256

DEP_TREE_SHA256="$(dependency_tree_sha256)"
printf '%s\n' "$DEP_TREE_SHA256" > taskmarket-dependency-tree.sha256
forge build

printf '%s\n' "$DIR" > "$STATE_FILE"
log "pinned project built at $DIR"
log "dependency tree locked: $DEP_TREE_SHA256"
printf '%s\n' "$DIR"
