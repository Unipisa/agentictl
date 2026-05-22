#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

USER_NAME="agentictl"
READONLY_USER_NAME=""
ACTION_USER_NAME=""
BASE_DIR="/opt/agentictl"
READONLY_PUBLIC_KEY_FILE=""
ACTION_PUBLIC_KEY_FILE=""
SSH_FROM=""
SPLIT_USERS="false"
SUDOERS_FILE="/etc/sudoers.d/agentictl"
SHARED_GROUP_NAME=""
READONLY_EXTRA_GROUPS=""
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="nvtop htop jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
ALLOW_READ_ROOTS="/var/log /etc"
ALLOW_LOG_ROOTS="/var/log"
DENY_READ_PATHS="/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  sudo install/install-node.sh --readonly-public-key-file id_agentictl_ro.pub [options]

Options:
  --action-public-key-file PATH     Optional second key for mutating actions.
  --user NAME                       Dedicated system user or split-user prefix, default: agentictl.
  --split-users                     Use separate Unix users for readonly and action SSH.
  --readonly-user NAME              Readonly Unix user when using --split-users.
  --action-user NAME                Action Unix user when using --split-users.
  --readonly-extra-groups LIST      Existing Unix groups to add readonly user to, e.g. "adm systemd-journal".
  --base-dir PATH                   Install prefix, default: /opt/agentictl.
  --ssh-from CIDR_OR_HOST_PATTERN   Optional authorized_keys from="..." restriction.
  --allow-service-restart LIST      Space-separated systemd service allowlist.
  --allow-package-install LIST      Space-separated package allowlist.
  --allow-config-targets LIST       Space-separated config target allowlist.
  --allow-read-roots LIST           Space-separated read-only filesystem roots.
  --allow-log-roots LIST            Space-separated log-read roots.
  --deny-read-paths LIST            Space-separated denied read paths.
USAGE
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --readonly-public-key-file) READONLY_PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
    --action-public-key-file) ACTION_PUBLIC_KEY_FILE="${2:-}"; shift 2 ;;
    --user) USER_NAME="${2:-}"; shift 2 ;;
    --split-users) SPLIT_USERS="true"; shift ;;
    --readonly-user) READONLY_USER_NAME="${2:-}"; shift 2 ;;
    --action-user) ACTION_USER_NAME="${2:-}"; shift 2 ;;
    --readonly-extra-groups) READONLY_EXTRA_GROUPS="${2:-}"; shift 2 ;;
    --base-dir) BASE_DIR="${2:-}"; shift 2 ;;
    --ssh-from) SSH_FROM="${2:-}"; shift 2 ;;
    --allow-service-restart) ALLOW_SERVICE_RESTART="${2:-}"; shift 2 ;;
    --allow-package-install) ALLOW_PACKAGE_INSTALL="${2:-}"; shift 2 ;;
    --allow-config-targets) ALLOW_CONFIG_TARGETS="${2:-}"; shift 2 ;;
    --allow-read-roots) ALLOW_READ_ROOTS="${2:-}"; shift 2 ;;
    --allow-log-roots) ALLOW_LOG_ROOTS="${2:-}"; shift 2 ;;
    --deny-read-paths) DENY_READ_PATHS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || fail "run as root"
[[ -n "$READONLY_PUBLIC_KEY_FILE" ]] || fail "--readonly-public-key-file is required"
[[ -r "$READONLY_PUBLIC_KEY_FILE" ]] || fail "readonly public key file not readable"
[[ -z "$ACTION_PUBLIC_KEY_FILE" || -r "$ACTION_PUBLIC_KEY_FILE" ]] || fail "action public key file not readable"
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "unsafe user name"
[[ "$USER_NAME" != "root" ]] || fail "--user root is not allowed"
if [[ "$SPLIT_USERS" == "true" ]]; then
  READONLY_USER_NAME="${READONLY_USER_NAME:-$USER_NAME-ro}"
  ACTION_USER_NAME="${ACTION_USER_NAME:-$USER_NAME-act}"
  SHARED_GROUP_NAME="${USER_NAME%\$}-audit"
else
  [[ -z "$READONLY_USER_NAME" && -z "$ACTION_USER_NAME" ]] || fail "--readonly-user and --action-user require --split-users"
  READONLY_USER_NAME="$USER_NAME"
  ACTION_USER_NAME="$USER_NAME"
fi
[[ "$READONLY_USER_NAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "unsafe readonly user name"
[[ "$ACTION_USER_NAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "unsafe action user name"
[[ "$READONLY_USER_NAME" != "root" && "$ACTION_USER_NAME" != "root" ]] || fail "root runtime users are not allowed"
[[ -z "$SHARED_GROUP_NAME" || "$SHARED_GROUP_NAME" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "unsafe shared audit group name"
[[ "$BASE_DIR" = /* && "$BASE_DIR" != *[[:space:]]* ]] || fail "--base-dir must be an absolute path without whitespace"

need_cmd install
need_cmd mkdir
need_cmd useradd
need_cmd usermod
need_cmd getent
need_cmd groupadd

ensure_user() {
  local user="$1"
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "/var/lib/$user" --shell /bin/sh "$user"
  else
    usermod --shell /bin/sh "$user"
  fi
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

user_group() {
  id -gn "$1"
}

ensure_group() {
  local group="$1"
  if ! getent group "$group" >/dev/null 2>&1; then
    groupadd --system "$group"
  fi
}

add_user_to_existing_groups() {
  local user="$1" groups="$2" group old_ifs
  old_ifs="$IFS"
  IFS=' '
  for group in $groups; do
    IFS="$old_ifs"
    [[ -n "$group" ]] || { IFS=' '; continue; }
    [[ "$group" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail "unsafe readonly extra group name: $group"
    getent group "$group" >/dev/null 2>&1 || fail "readonly extra group does not exist: $group"
    usermod -a -G "$group" "$user"
    IFS=' '
  done
  IFS="$old_ifs"
}

ensure_user "$READONLY_USER_NAME"
if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  ensure_user "$ACTION_USER_NAME"
fi

if [[ "$SPLIT_USERS" == "true" ]]; then
  ensure_group "$SHARED_GROUP_NAME"
  usermod -a -G "$SHARED_GROUP_NAME" "$READONLY_USER_NAME"
  if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
    usermod -a -G "$SHARED_GROUP_NAME" "$ACTION_USER_NAME"
  fi
else
  SHARED_GROUP_NAME="$(user_group "$READONLY_USER_NAME")"
fi

add_user_to_existing_groups "$READONLY_USER_NAME" "$READONLY_EXTRA_GROUPS"

STATE_OWNER="$READONLY_USER_NAME"
if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  STATE_OWNER="$ACTION_USER_NAME"
fi
STATE_GROUP="$(user_group "$STATE_OWNER")"

install -d -m 0755 -o root -g root "$BASE_DIR" "$BASE_DIR/bin" "$BASE_DIR/config"
install -d -m 0750 -o root -g "$SHARED_GROUP_NAME" "$BASE_DIR/state"
install -d -m 0750 -o "$STATE_OWNER" -g "$STATE_GROUP" "$BASE_DIR/state/backups" "$BASE_DIR/state/incoming"
if [[ -e "$BASE_DIR/state/audit.log" ]]; then
  chown root:"$SHARED_GROUP_NAME" "$BASE_DIR/state/audit.log"
  chmod 0660 "$BASE_DIR/state/audit.log"
else
  install -m 0660 -o root -g "$SHARED_GROUP_NAME" /dev/null "$BASE_DIR/state/audit.log"
fi
install -m 0755 -o root -g root "$REPO_DIR/bin/agentictl" "$BASE_DIR/bin/agentictl"
install -m 0755 -o root -g root "$REPO_DIR/bin/agentictl-readonly" "$BASE_DIR/bin/agentictl-readonly"
install -m 0755 -o root -g root "$REPO_DIR/bin/agentictl-act" "$BASE_DIR/bin/agentictl-act"

if [[ ! -e "$BASE_DIR/config/policy.env" ]]; then
  tmp_policy="$(mktemp)"
  {
    printf '# Managed by agentictl install-node.sh\n'
    printf 'ALLOW_SERVICE_RESTART=%q\n' "$ALLOW_SERVICE_RESTART"
    printf 'ALLOW_PACKAGE_INSTALL=%q\n' "$ALLOW_PACKAGE_INSTALL"
    printf 'AGENTICTL_PACKAGE_MANAGER=auto\n'
    printf 'ALLOW_CONFIG_TARGETS=%q\n' "$ALLOW_CONFIG_TARGETS"
    printf 'AGENTICTL_MAX_CONFIG_BYTES=1048576\n'
    printf 'ALLOW_READ_ROOTS=%q\n' "$ALLOW_READ_ROOTS"
    printf 'ALLOW_LOG_ROOTS=%q\n' "$ALLOW_LOG_ROOTS"
    printf 'DENY_READ_PATHS=%q\n' "$DENY_READ_PATHS"
    printf 'AGENTICTL_MAX_READ_BYTES=262144\n'
    printf 'AGENTICTL_MAX_LIST_ENTRIES=2000\n'
    printf 'AGENTICTL_MAX_LIST_DEPTH=5\n'
  } > "$tmp_policy"
  install -m 0644 -o root -g root "$tmp_policy" "$BASE_DIR/config/policy.env"
  rm -f "$tmp_policy"
else
  chmod 0644 "$BASE_DIR/config/policy.env"
  chown root:root "$BASE_DIR/config/policy.env"
fi

build_key_line() {
  local mode="$1" key_file="$2" key_line options
  key_line="$(head -n 1 "$key_file" | tr -d '\r\n')"
  [[ "$key_line" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]] ]] || fail "unsupported or invalid public key: $key_file"
  options="command=\"$BASE_DIR/bin/agentictl $mode\",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding"
  if [[ -n "$SSH_FROM" ]]; then
    options="from=\"$SSH_FROM\",$options"
  fi
  printf '%s %s agentictl-managed-%s\n' "$options" "$key_line" "$mode"
}

install_key_for_user() {
  local user="$1" mode="$2" key_file="$3"
  local home group auth_file auth_tmp
  home="$(user_home "$user")"
  group="$(user_group "$user")"
  install -d -m 0700 -o "$user" -g "$group" "$home/.ssh"
  auth_file="$home/.ssh/authorized_keys"
  auth_tmp="$(mktemp)"
  if [[ -f "$auth_file" ]]; then
    grep -v "agentictl-managed-$mode" "$auth_file" > "$auth_tmp" || true
  fi
  build_key_line "$mode" "$key_file" >> "$auth_tmp"
  install -m 0600 -o "$user" -g "$group" "$auth_tmp" "$auth_file"
  rm -f "$auth_tmp"
}

remove_key_for_user() {
  local user="$1" mode="$2"
  local home group auth_file auth_tmp
  id "$user" >/dev/null 2>&1 || return 0
  home="$(user_home "$user")"
  group="$(user_group "$user")"
  auth_file="$home/.ssh/authorized_keys"
  [[ -f "$auth_file" ]] || return 0
  auth_tmp="$(mktemp)"
  grep -v "agentictl-managed-$mode" "$auth_file" > "$auth_tmp" || true
  install -m 0600 -o "$user" -g "$group" "$auth_tmp" "$auth_file"
  rm -f "$auth_tmp"
}

install_key_for_user "$READONLY_USER_NAME" readonly "$READONLY_PUBLIC_KEY_FILE"
if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  install_key_for_user "$ACTION_USER_NAME" act "$ACTION_PUBLIC_KEY_FILE"
else
  remove_key_for_user "$ACTION_USER_NAME" act
fi

if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]] && command -v sudo >/dev/null 2>&1; then
  sudoers_tmp="$(mktemp)"
  printf '%s ALL=(root) NOPASSWD: %s/bin/agentictl-act *\n' "$ACTION_USER_NAME" "$BASE_DIR" > "$sudoers_tmp"
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf "$sudoers_tmp" >/dev/null
  fi
  install -m 0440 -o root -g root "$sudoers_tmp" "$SUDOERS_FILE"
  rm -f "$sudoers_tmp"
elif [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  printf 'warning: sudo not found; --execute actions must run as root by another confinement mechanism\n' >&2
else
  rm -f "$SUDOERS_FILE"
fi

printf 'installed agentictl\n'
printf '  readonly user: %s\n' "$READONLY_USER_NAME"
if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  printf '  action user: %s\n' "$ACTION_USER_NAME"
fi
printf '  audit group: %s\n' "$SHARED_GROUP_NAME"
if [[ -n "$READONLY_EXTRA_GROUPS" ]]; then
  printf '  readonly extra groups: %s\n' "$READONLY_EXTRA_GROUPS"
fi
printf '  base: %s\n' "$BASE_DIR"
printf '  readonly ssh: ssh %s@HOST health\n' "$READONLY_USER_NAME"
if [[ -n "$ACTION_PUBLIC_KEY_FILE" ]]; then
  printf '  action ssh:   ssh -i ACTION_KEY %s@HOST service-restart --unit ollama.service --dry-run\n' "$ACTION_USER_NAME"
fi
