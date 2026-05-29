#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "agentictl-node-upgrade.sh requires bash; run: bash $0 ..." >&2
  exit 2
fi
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/../resources" ]]; then
  SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
elif [[ -n "${AGENTICTL_SKILL_DIR:-}" && -d "$AGENTICTL_SKILL_DIR/resources" ]]; then
  SKILL_DIR="$AGENTICTL_SKILL_DIR"
elif [[ -d "$SCRIPT_DIR/../share/agentictl-ssh/resources" ]]; then
  SKILL_DIR="$(cd -- "$SCRIPT_DIR/../share/agentictl-ssh" && pwd)"
else
  SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
fi

HOST=""
ADMIN_USER="admin"
VERSION="0.1.0"
TARBALL="$SKILL_DIR/resources/dist/agentictl-0.1.0.tar.gz"
MANIFEST="$SKILL_DIR/resources/dist/agentictl-0.1.0.manifest"
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
VERIFY_RO=""
VERIFY_ACT=""
EXECUTE="false"
REMOTE_DIR="/tmp"

usage() {
  cat <<'USAGE'
Usage:
  agentictl-node-upgrade.sh --host HOST [options]

By default, prints a copy/paste upgrade plan. With --execute, copies the
vendored agentictl tarball to the node, verifies its checksum remotely, runs
the installer through an existing admin SSH account, and optionally verifies
read-only/action aliases.

Options:
  --host HOST
  --admin-user USER
  --tarball PATH
  --manifest PATH
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
  --verify-ro ALIAS
  --verify-act ALIAS
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
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
    --verify-ro) VERIFY_RO="${2:-}"; shift 2 ;;
    --verify-act) VERIFY_ACT="${2:-}"; shift 2 ;;
    --execute) EXECUTE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$HOST" ]] || fail "--host is required"
[[ -n "$ADMIN_USER" ]] || fail "--admin-user is required"
[[ -r "$TARBALL" ]] || fail "tarball not readable: $TARBALL"
[[ -r "$READONLY_PUBLIC_KEY_FILE" ]] || fail "readonly public key not readable: $READONLY_PUBLIC_KEY_FILE"
if [[ "$READONLY_ONLY" != "true" ]]; then
  [[ -r "$ACTION_PUBLIC_KEY_FILE" ]] || fail "action public key not readable: $ACTION_PUBLIC_KEY_FILE"
fi
[[ "$ALLOW_PACKAGE_UPGRADE_ALL" == "true" || "$ALLOW_PACKAGE_UPGRADE_ALL" == "false" ]] || fail "--allow-package-upgrade-all must be true or false"
validate_id "$HOST" "--host"
validate_id "$ADMIN_USER" "--admin-user"
[[ -z "$VERIFY_RO" ]] || validate_id "$VERIFY_RO" "--verify-ro"
[[ -z "$VERIFY_ACT" ]] || validate_id "$VERIFY_ACT" "--verify-act"

TARBALL_BASENAME="agentictl-$VERSION.tar.gz"
REMOTE_TARBALL="$REMOTE_DIR/$TARBALL_BASENAME"
REMOTE_RO_KEY="$REMOTE_DIR/agentictl_ro.pub"
REMOTE_ACT_KEY="$REMOTE_DIR/agentictl_act.pub"
LOCAL_SHA256="$(checksum_file "$TARBALL")"
if expected="$(manifest_sha256 "$MANIFEST")"; then
  [[ "$expected" == "$LOCAL_SHA256" ]] || fail "tarball checksum does not match manifest"
fi

print_remote_script() {
  printf 'set -euo pipefail\n'
  printf 'cd %s\n' "$(sq "$REMOTE_DIR")"
  printf 'echo %s | sha256sum -c - >/dev/null\n' "$(sq "$LOCAL_SHA256  $TARBALL_BASENAME")"
  printf 'rm -rf %s\n' "$(sq "agentictl-$VERSION")"
  printf 'tar -xzf %s\n' "$(sq "$TARBALL_BASENAME")"
  printf 'cd %s\n' "$(sq "agentictl-$VERSION")"
  printf 'sudo install/install-node.sh \\\n'
  printf '  --split-users \\\n'
  printf '  --readonly-public-key-file %s \\\n' "$(sq "$REMOTE_RO_KEY")"
  if [[ "$READONLY_ONLY" != "true" ]]; then
    printf '  --action-public-key-file %s \\\n' "$(sq "$REMOTE_ACT_KEY")"
  fi
  if [[ -n "$READONLY_EXTRA_GROUPS" ]]; then
    printf '  --readonly-extra-groups %s \\\n' "$(sq "$READONLY_EXTRA_GROUPS")"
  fi
  printf '  --allow-service-restart %s \\\n' "$(sq "$ALLOW_SERVICE_RESTART")"
  printf '  --allow-package-install %s \\\n' "$(sq "$ALLOW_PACKAGE_INSTALL")"
  printf '  --allow-package-upgrade %s \\\n' "$(sq "$ALLOW_PACKAGE_UPGRADE")"
  printf '  --allow-package-upgrade-all %s \\\n' "$(sq "$ALLOW_PACKAGE_UPGRADE_ALL")"
  printf '  --allow-config-targets %s \\\n' "$(sq "$ALLOW_CONFIG_TARGETS")"
  printf '  --allow-read-roots %s \\\n' "$(sq "$ALLOW_READ_ROOTS")"
  printf '  --allow-log-roots %s\n' "$(sq "$ALLOW_LOG_ROOTS")"
}

print_plan() {
  cat <<'INTRO'
# agentictl node upgrade plan.
# Run from the OpenClaw host. It uses the admin SSH account only for upgrade.

INTRO
  printf 'scp %s %s\n' "$(sq "$TARBALL")" "$(sq "$ADMIN_USER@$HOST:$REMOTE_TARBALL")"
  printf 'scp %s %s\n' "$(sq "$READONLY_PUBLIC_KEY_FILE")" "$(sq "$ADMIN_USER@$HOST:$REMOTE_RO_KEY")"
  if [[ "$READONLY_ONLY" != "true" ]]; then
    printf 'scp %s %s\n' "$(sq "$ACTION_PUBLIC_KEY_FILE")" "$(sq "$ADMIN_USER@$HOST:$REMOTE_ACT_KEY")"
  fi
  printf "ssh %s 'bash -s' <<'AGENTICTL_REMOTE_UPGRADE'\n" "$(sq "$ADMIN_USER@$HOST")"
  print_remote_script
  printf 'AGENTICTL_REMOTE_UPGRADE\n'
  if [[ -n "$VERIFY_RO" ]]; then
    printf '\nssh %s capabilities\n' "$(sq "$VERIFY_RO")"
    printf 'ssh %s health\n' "$(sq "$VERIFY_RO")"
    printf 'ssh %s package-upgrades --limit 100\n' "$(sq "$VERIFY_RO")"
  fi
  if [[ -n "$VERIFY_ACT" ]]; then
    printf 'ssh %s capabilities\n' "$(sq "$VERIFY_ACT")"
    printf 'ssh %s package-upgrade --name htop --dry-run\n' "$(sq "$VERIFY_ACT")"
  fi
}

if [[ "$EXECUTE" != "true" ]]; then
  print_plan
  exit 0
fi

scp "$TARBALL" "$ADMIN_USER@$HOST:$REMOTE_TARBALL"
scp "$READONLY_PUBLIC_KEY_FILE" "$ADMIN_USER@$HOST:$REMOTE_RO_KEY"
if [[ "$READONLY_ONLY" != "true" ]]; then
  scp "$ACTION_PUBLIC_KEY_FILE" "$ADMIN_USER@$HOST:$REMOTE_ACT_KEY"
fi

remote_script="$(print_remote_script)"
ssh "$ADMIN_USER@$HOST" 'bash -s' <<< "$remote_script"

if [[ -n "$VERIFY_RO" ]]; then
  ssh "$VERIFY_RO" capabilities
  ssh "$VERIFY_RO" health
  ssh "$VERIFY_RO" package-upgrades --limit 100
fi
if [[ -n "$VERIFY_ACT" ]]; then
  ssh "$VERIFY_ACT" capabilities
  ssh "$VERIFY_ACT" package-upgrade --name htop --dry-run
fi
