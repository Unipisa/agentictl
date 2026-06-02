#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "agentictl-fleet-sync.sh requires bash; run: bash $0 ..." >&2
  exit 2
fi
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODE="upgrade"
SOURCE="skill"
OPENCLAW_WORKSPACE=""
SKILL_DIR=""
REPO_DIR=""
GIT_PULL="false"
BIN_DIR="${HOME:-.}/.local/bin"
ADMIN_USER=""
ADMIN_IDENTITY=""
NODES=()
VERSION="0.1.0"
TARBALL=""
MANIFEST=""
READONLY_PUBLIC_KEY_FILE="${HOME:-.}/.ssh/agentictl_ro.pub"
ACTION_PUBLIC_KEY_FILE="${HOME:-.}/.ssh/agentictl_act.pub"
READONLY_ONLY="false"
READONLY_EXTRA_GROUPS=""
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="htop jq"
ALLOW_PACKAGE_UPGRADE="htop jq"
ALLOW_PACKAGE_UPGRADE_ALL="false"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
ALLOW_READ_ROOTS="/var/log /etc"
ALLOW_LOG_ROOTS="/var/log"
REMOVE_USERS="false"
REMOVE_BASE_DIR="false"
EXECUTE="false"

usage() {
  cat <<'USAGE'
Usage:
  agentictl-fleet-sync.sh --admin-user USER --node HOST:RO_ALIAS:ACT_ALIAS [options]

Modes:
  --mode upgrade       Sync OpenClaw skill/tools and upgrade node-side agentictl.
  --mode uninstall     Remove node-side agentictl managed access; optional local skill removal.

Version sources:
  --source skill       Default. Use the payload bundled in the current skill.
  --source repo        Use --repo-dir, optionally --git-pull, then rebuild the bundled payload.
  --source tarball     Use explicit --tarball and --manifest paths.

Options:
  --openclaw-workspace PATH
  --skill-dir PATH
  --repo-dir PATH
  --git-pull
  --bin-dir PATH
  --admin-user USER
  --admin-identity PATH
  --node HOST[:RO_ALIAS[:ACT_ALIAS]]
  --readonly-public-key-file PATH
  --action-public-key-file PATH
  --readonly-only
  --readonly-extra-groups LIST
  --allow-service-restart LIST
  --allow-package-install LIST
  --allow-package-upgrade LIST
  --allow-package-upgrade-all BOOL
  --allow-config-targets LIST
  --allow-read-roots LIST
  --allow-log-roots LIST
  --remove-users              With --mode uninstall, remove dedicated runtime users.
  --remove-base-dir           With --mode uninstall, remove /opt/agentictl state/config too.
  --remove-openclaw-skill     With --mode uninstall, remove local OpenClaw skill and helper files.
  --execute
USAGE
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

sq() {
  local value="${1-}"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

checksum_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required"
  fi
}

manifest_sha256() {
  local path="$1" line
  [[ -r "$path" ]] || return 1
  line="$(grep -E '^SHA256=' "$path" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1
  printf '%s' "${line#SHA256=}"
}

validate_id() {
  local value="$1" name="$2"
  [[ "$value" =~ ^[A-Za-z0-9_.@:-]+$ ]] || fail "invalid $name"
}

resolve_default_skill_dir() {
  if [[ -n "$SKILL_DIR" ]]; then
    printf '%s' "$SKILL_DIR"
  elif [[ -n "$OPENCLAW_WORKSPACE" && -d "$OPENCLAW_WORKSPACE/skills/agentictl-ssh/resources" ]]; then
    printf '%s' "$OPENCLAW_WORKSPACE/skills/agentictl-ssh"
  elif [[ -d "$SCRIPT_DIR/../resources" ]]; then
    cd -- "$SCRIPT_DIR/.." && pwd
  elif [[ -d "$SCRIPT_DIR/../share/agentictl-ssh/resources" ]]; then
    cd -- "$SCRIPT_DIR/../share/agentictl-ssh" && pwd
  else
    return 1
  fi
}

resolve_upgrade_tool() {
  if [[ -x "$SCRIPT_DIR/agentictl-node-upgrade.sh" || -r "$SCRIPT_DIR/agentictl-node-upgrade.sh" ]]; then
    printf '%s' "$SCRIPT_DIR/agentictl-node-upgrade.sh"
  elif command -v agentictl-node-upgrade.sh >/dev/null 2>&1; then
    command -v agentictl-node-upgrade.sh
  else
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --uninstall) MODE="uninstall"; shift ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --openclaw-workspace) OPENCLAW_WORKSPACE="${2:-}"; shift 2 ;;
    --skill-dir) SKILL_DIR="${2:-}"; shift 2 ;;
    --repo-dir) REPO_DIR="${2:-}"; SOURCE="repo"; shift 2 ;;
    --git-pull) GIT_PULL="true"; shift ;;
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
    --admin-identity) ADMIN_IDENTITY="${2:-}"; shift 2 ;;
    --node) NODES+=("${2:-}"); shift 2 ;;
    --tarball) TARBALL="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --readonly-public-key-file) READONLY_PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
    --action-public-key-file) ACTION_PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
    --readonly-only) READONLY_ONLY="true"; shift ;;
    --readonly-extra-groups) READONLY_EXTRA_GROUPS="${2:-}"; shift 2 ;;
    --allow-service-restart) ALLOW_SERVICE_RESTART="${2:-}"; shift 2 ;;
    --allow-package-install) ALLOW_PACKAGE_INSTALL="${2:-}"; shift 2 ;;
    --allow-package-upgrade) ALLOW_PACKAGE_UPGRADE="${2:-}"; shift 2 ;;
    --allow-package-upgrade-all) ALLOW_PACKAGE_UPGRADE_ALL="${2:-}"; shift 2 ;;
    --allow-config-targets) ALLOW_CONFIG_TARGETS="${2:-}"; shift 2 ;;
    --allow-read-roots) ALLOW_READ_ROOTS="${2:-}"; shift 2 ;;
    --allow-log-roots) ALLOW_LOG_ROOTS="${2:-}"; shift 2 ;;
    --remove-users) REMOVE_USERS="true"; shift ;;
    --remove-base-dir) REMOVE_BASE_DIR="true"; shift ;;
    --remove-openclaw-skill) REMOVE_OPENCLAW_SKILL="true"; shift ;;
    --execute) EXECUTE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

REMOVE_OPENCLAW_SKILL="${REMOVE_OPENCLAW_SKILL:-false}"
[[ "$MODE" == "upgrade" || "$MODE" == "uninstall" ]] || fail "--mode must be upgrade or uninstall"
[[ "$SOURCE" == "skill" || "$SOURCE" == "repo" || "$SOURCE" == "tarball" ]] || fail "--source must be skill, repo, or tarball"
[[ -n "$ADMIN_USER" ]] || fail "--admin-user is required"
validate_id "$ADMIN_USER" "--admin-user"
[[ -z "$ADMIN_IDENTITY" || -r "$ADMIN_IDENTITY" ]] || fail "admin identity not readable: $ADMIN_IDENTITY"
[[ "${#NODES[@]}" -gt 0 ]] || fail "at least one --node is required"
[[ "$ALLOW_PACKAGE_UPGRADE_ALL" == "true" || "$ALLOW_PACKAGE_UPGRADE_ALL" == "false" ]] || fail "--allow-package-upgrade-all must be true or false"

SKILL_SOURCE_DIR=""
case "$SOURCE" in
  repo)
    [[ -n "$REPO_DIR" ]] || fail "--repo-dir is required for --source repo"
    [[ -d "$REPO_DIR/skills/agentictl-ssh/resources" ]] || fail "repo skill resources not found: $REPO_DIR"
    SKILL_SOURCE_DIR="$(cd -- "$REPO_DIR/skills/agentictl-ssh" && pwd)"
    TARBALL="$SKILL_SOURCE_DIR/resources/dist/agentictl-$VERSION.tar.gz"
    MANIFEST="$SKILL_SOURCE_DIR/resources/dist/agentictl-$VERSION.manifest"
    ;;
  skill)
    SKILL_SOURCE_DIR="$(resolve_default_skill_dir)" || fail "skill resources not found; pass --skill-dir or --source repo"
    TARBALL="${TARBALL:-$SKILL_SOURCE_DIR/resources/dist/agentictl-$VERSION.tar.gz}"
    MANIFEST="${MANIFEST:-$SKILL_SOURCE_DIR/resources/dist/agentictl-$VERSION.manifest}"
    ;;
  tarball)
    [[ -n "$TARBALL" && -n "$MANIFEST" ]] || fail "--tarball and --manifest are required for --source tarball"
    ;;
esac

[[ -r "$TARBALL" ]] || fail "tarball not readable: $TARBALL"
[[ -r "$MANIFEST" ]] || fail "manifest not readable: $MANIFEST"
if expected="$(manifest_sha256 "$MANIFEST")"; then
  actual="$(checksum_file "$TARBALL")"
  [[ "$expected" == "$actual" ]] || fail "tarball checksum does not match manifest"
fi

if [[ "$MODE" == "upgrade" ]]; then
  [[ -r "$READONLY_PUBLIC_KEY_FILE" ]] || fail "readonly public key not readable: $READONLY_PUBLIC_KEY_FILE"
  if [[ "$READONLY_ONLY" != "true" ]]; then
    [[ -r "$ACTION_PUBLIC_KEY_FILE" ]] || fail "action public key not readable: $ACTION_PUBLIC_KEY_FILE"
  fi
fi

UPGRADE_TOOL="$(resolve_upgrade_tool)" || fail "agentictl-node-upgrade.sh not found"

print_header() {
  printf '# agentictl fleet %s plan\n' "$MODE"
  printf '# version source: %s\n' "$SOURCE"
  printf '# tarball: %s\n' "$TARBALL"
  printf '# manifest: %s\n' "$MANIFEST"
  if [[ -n "$OPENCLAW_WORKSPACE" ]]; then
    printf '# OpenClaw workspace: %s\n' "$OPENCLAW_WORKSPACE"
  fi
  printf '\n'
}

print_local_sync_plan() {
  [[ "$MODE" == "upgrade" ]] || return 0
  if [[ "$SOURCE" == "repo" && "$GIT_PULL" == "true" ]]; then
    printf 'git -C %s pull --ff-only\n' "$(sq "$REPO_DIR")"
    printf 'bash %s\n' "$(sq "$REPO_DIR/packaging/build-tarball.sh")"
  fi
  if [[ -n "$OPENCLAW_WORKSPACE" && -n "$SKILL_SOURCE_DIR" ]]; then
    printf 'mkdir -p %s\n' "$(sq "$OPENCLAW_WORKSPACE/skills")"
    if command -v rsync >/dev/null 2>&1; then
      printf 'rsync -a --delete %s %s\n' "$(sq "$SKILL_SOURCE_DIR/")" "$(sq "$OPENCLAW_WORKSPACE/skills/agentictl-ssh/")"
    else
      printf 'rm -rf %s\n' "$(sq "$OPENCLAW_WORKSPACE/skills/agentictl-ssh")"
      printf 'cp -a %s %s\n' "$(sq "$SKILL_SOURCE_DIR")" "$(sq "$OPENCLAW_WORKSPACE/skills/agentictl-ssh")"
    fi
    printf 'bash %s --bin-dir %s\n' "$(sq "$OPENCLAW_WORKSPACE/skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh")" "$(sq "$BIN_DIR")"
  fi
}

run_local_sync() {
  [[ "$MODE" == "upgrade" ]] || return 0
  if [[ "$SOURCE" == "repo" && "$GIT_PULL" == "true" ]]; then
    git -C "$REPO_DIR" pull --ff-only
    bash "$REPO_DIR/packaging/build-tarball.sh"
  fi
  if [[ -n "$OPENCLAW_WORKSPACE" && -n "$SKILL_SOURCE_DIR" ]]; then
    mkdir -p "$OPENCLAW_WORKSPACE/skills"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$SKILL_SOURCE_DIR/" "$OPENCLAW_WORKSPACE/skills/agentictl-ssh/"
    else
      [[ "$OPENCLAW_WORKSPACE/skills/agentictl-ssh" == */skills/agentictl-ssh ]] || fail "refusing unsafe skill target"
      rm -rf -- "$OPENCLAW_WORKSPACE/skills/agentictl-ssh"
      cp -a "$SKILL_SOURCE_DIR" "$OPENCLAW_WORKSPACE/skills/agentictl-ssh"
    fi
    bash "$OPENCLAW_WORKSPACE/skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh" --bin-dir "$BIN_DIR"
  fi
}

node_host() {
  local spec="$1"
  printf '%s' "${spec%%:*}"
}

node_ro() {
  local spec="$1" rest
  rest="${spec#*:}"
  [[ "$rest" != "$spec" ]] || { printf ''; return 0; }
  printf '%s' "${rest%%:*}"
}

node_act() {
  local spec="$1" rest
  rest="${spec#*:}"
  [[ "$rest" != "$spec" ]] || { printf ''; return 0; }
  rest="${rest#*:}"
  [[ "$rest" != "${spec#*:}" ]] || { printf ''; return 0; }
  printf '%s' "$rest"
}

node_upgrade_args() {
  local host="$1" ro="$2" act="$3"
  printf '%s\0' --host "$host" --admin-user "$ADMIN_USER" --tarball "$TARBALL" --manifest "$MANIFEST"
  [[ -z "$ADMIN_IDENTITY" ]] || printf '%s\0' --admin-identity "$ADMIN_IDENTITY"
  printf '%s\0' --readonly-public-key-file "$READONLY_PUBLIC_KEY_FILE"
  if [[ "$READONLY_ONLY" == "true" ]]; then
    printf '%s\0' --readonly-only
  else
    printf '%s\0' --action-public-key-file "$ACTION_PUBLIC_KEY_FILE"
  fi
  [[ -z "$READONLY_EXTRA_GROUPS" ]] || printf '%s\0' --readonly-extra-groups "$READONLY_EXTRA_GROUPS"
  printf '%s\0' --allow-service-restart "$ALLOW_SERVICE_RESTART"
  printf '%s\0' --allow-package-install "$ALLOW_PACKAGE_INSTALL"
  printf '%s\0' --allow-package-upgrade "$ALLOW_PACKAGE_UPGRADE"
  printf '%s\0' --allow-package-upgrade-all "$ALLOW_PACKAGE_UPGRADE_ALL"
  printf '%s\0' --allow-config-targets "$ALLOW_CONFIG_TARGETS"
  printf '%s\0' --allow-read-roots "$ALLOW_READ_ROOTS"
  printf '%s\0' --allow-log-roots "$ALLOW_LOG_ROOTS"
  [[ -z "$ro" ]] || printf '%s\0' --verify-ro "$ro"
  [[ -z "$act" || "$READONLY_ONLY" == "true" ]] || printf '%s\0' --verify-act "$act"
}

run_node_upgrade() {
  local spec="$1" host ro act
  host="$(node_host "$spec")"; ro="$(node_ro "$spec")"; act="$(node_act "$spec")"
  validate_id "$host" "--node host"
  [[ -z "$ro" ]] || validate_id "$ro" "--node ro alias"
  [[ -z "$act" ]] || validate_id "$act" "--node act alias"
  mapfile -d '' args < <(node_upgrade_args "$host" "$ro" "$act")
  if [[ "$EXECUTE" == "true" ]]; then
    bash "$UPGRADE_TOOL" "${args[@]}" --execute
  else
    bash "$UPGRADE_TOOL" "${args[@]}"
  fi
}

ssh_plan_prefix() {
  if [[ -n "$ADMIN_IDENTITY" ]]; then
    printf 'ssh -i %s' "$(sq "$ADMIN_IDENTITY")"
  else
    printf 'ssh'
  fi
}

scp_plan_prefix() {
  if [[ -n "$ADMIN_IDENTITY" ]]; then
    printf 'scp -i %s' "$(sq "$ADMIN_IDENTITY")"
  else
    printf 'scp'
  fi
}

share_dir_for_bin() {
  local parent
  parent="${BIN_DIR%/*}"
  [[ "$parent" != "$BIN_DIR" && -n "$parent" ]] || parent="."
  printf '%s/share/agentictl-ssh' "$parent"
}

print_uninstall_remote_script() {
  local checksum="$1" tarball_name
  tarball_name="$(basename "$TARBALL")"
  printf 'set -euo pipefail\n'
  printf 'cd /tmp\n'
  printf 'echo %s | sha256sum -c - >/dev/null\n' "$(sq "$checksum  $tarball_name")"
  printf 'rm -rf %s\n' "$(sq "agentictl-$VERSION")"
  printf 'tar -xzf %s\n' "$(sq "$tarball_name")"
  printf 'cd %s\n' "$(sq "agentictl-$VERSION")"
  printf 'sudo install/install-node.sh --uninstall --split-users'
  [[ "$REMOVE_USERS" == "true" ]] && printf ' --remove-users'
  [[ "$REMOVE_BASE_DIR" == "true" ]] && printf ' --remove-base-dir'
  printf '\n'
}

run_node_uninstall() {
  local spec="$1" host checksum tarball_name target remote_script
  host="$(node_host "$spec")"
  validate_id "$host" "--node host"
  checksum="$(checksum_file "$TARBALL")"
  tarball_name="$(basename "$TARBALL")"
  target="$ADMIN_USER@$host"
  if [[ "$EXECUTE" != "true" ]]; then
    printf '# uninstall node: %s\n' "$host"
    printf '%s %s %s\n' "$(scp_plan_prefix)" "$(sq "$TARBALL")" "$(sq "$target:/tmp/$tarball_name")"
    printf "%s %s 'bash -s' <<'AGENTICTL_REMOTE_UNINSTALL'\n" "$(ssh_plan_prefix)" "$(sq "$target")"
    print_uninstall_remote_script "$checksum"
    printf 'AGENTICTL_REMOTE_UNINSTALL\n\n'
    return 0
  fi
  ssh_args=()
  scp_args=()
  [[ -z "$ADMIN_IDENTITY" ]] || { ssh_args=(-i "$ADMIN_IDENTITY"); scp_args=(-i "$ADMIN_IDENTITY"); }
  scp "${scp_args[@]}" "$TARBALL" "$target:/tmp/$tarball_name"
  remote_script="$(print_uninstall_remote_script "$checksum")"
  ssh "${ssh_args[@]}" "$target" 'bash -s' <<< "$remote_script"
}

print_local_uninstall_plan() {
  [[ "$MODE" == "uninstall" && "$REMOVE_OPENCLAW_SKILL" == "true" && -n "$OPENCLAW_WORKSPACE" ]] || return 0
  printf 'rm -rf %s\n' "$(sq "$OPENCLAW_WORKSPACE/skills/agentictl-ssh")"
  printf 'rm -f %s %s %s %s %s %s\n' \
    "$(sq "$BIN_DIR/agentictl-approval-tool.sh")" \
    "$(sq "$BIN_DIR/agentictl-node-tool.sh")" \
    "$(sq "$BIN_DIR/agentictl-ssh-tool.sh")" \
    "$(sq "$BIN_DIR/agentictl-bootstrap-instructions.sh")" \
    "$(sq "$BIN_DIR/agentictl-node-upgrade.sh")" \
    "$(sq "$BIN_DIR/agentictl-fleet-sync.sh")"
  printf 'rm -rf %s\n' "$(sq "$(share_dir_for_bin)")"
}

run_local_uninstall() {
  [[ "$MODE" == "uninstall" && "$REMOVE_OPENCLAW_SKILL" == "true" && -n "$OPENCLAW_WORKSPACE" ]] || return 0
  [[ "$OPENCLAW_WORKSPACE/skills/agentictl-ssh" == */skills/agentictl-ssh ]] || fail "refusing unsafe skill removal"
  rm -rf -- "$OPENCLAW_WORKSPACE/skills/agentictl-ssh"
  rm -f -- \
    "$BIN_DIR/agentictl-approval-tool.sh" \
    "$BIN_DIR/agentictl-node-tool.sh" \
    "$BIN_DIR/agentictl-ssh-tool.sh" \
    "$BIN_DIR/agentictl-bootstrap-instructions.sh" \
    "$BIN_DIR/agentictl-node-upgrade.sh" \
    "$BIN_DIR/agentictl-fleet-sync.sh"
  rm -rf -- "$(share_dir_for_bin)"
}

if [[ "$EXECUTE" != "true" ]]; then
  print_header
  print_local_sync_plan
  print_local_uninstall_plan
  for spec in "${NODES[@]}"; do
    if [[ "$MODE" == "upgrade" ]]; then
      run_node_upgrade "$spec"
    else
      run_node_uninstall "$spec"
    fi
  done
  exit 0
fi

run_local_sync
run_local_uninstall
for spec in "${NODES[@]}"; do
  if [[ "$MODE" == "upgrade" ]]; then
    run_node_upgrade "$spec"
  else
    run_node_uninstall "$spec"
  fi
done
