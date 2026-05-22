#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

HOST=""
ADMIN_USER="admin"
ALIAS_RO=""
ALIAS_ACT=""
ROLE=""
TARBALL="dist/agentictl-0.1.0.tar.gz"
READONLY_KEY="${HOME:-.}/.ssh/agentictl_ro"
ACTION_KEY="${HOME:-.}/.ssh/agentictl_act"
READONLY_ONLY="false"
READONLY_EXTRA_GROUPS=""
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="htop jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
ALLOW_READ_ROOTS="/var/log /etc"
ALLOW_LOG_ROOTS="/var/log"

usage() {
  cat <<'USAGE'
Usage:
  agentictl-bootstrap-instructions.sh --host HOST [options]

Prints copy/paste terminal commands for bootstrapping agentictl on a new node.

Options:
  --admin-user USER
  --alias-ro ALIAS
  --alias-act ALIAS
  --role TEXT
  --tarball PATH
  --readonly-key PATH
  --action-key PATH
  --readonly-only
  --readonly-extra-groups LIST
  --allow-service-restart LIST
  --allow-package-install LIST
  --allow-config-targets LIST
  --allow-read-roots LIST
  --allow-log-roots LIST
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

safe_alias() {
  local value="$1"
  value="${value#*@}"
  value="${value//[^A-Za-z0-9_.@:-]/-}"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --admin-user) ADMIN_USER="${2:-}"; shift 2 ;;
    --alias-ro) ALIAS_RO="${2:-}"; shift 2 ;;
    --alias-act) ALIAS_ACT="${2:-}"; shift 2 ;;
    --role) ROLE="${2:-}"; shift 2 ;;
    --tarball) TARBALL="${2:-}"; shift 2 ;;
    --readonly-key) READONLY_KEY="${2:-}"; shift 2 ;;
    --action-key) ACTION_KEY="${2:-}"; shift 2 ;;
    --readonly-only) READONLY_ONLY="true"; shift ;;
    --readonly-extra-groups) READONLY_EXTRA_GROUPS="${2:-}"; shift 2 ;;
    --allow-service-restart) ALLOW_SERVICE_RESTART="${2:-}"; shift 2 ;;
    --allow-package-install) ALLOW_PACKAGE_INSTALL="${2:-}"; shift 2 ;;
    --allow-config-targets) ALLOW_CONFIG_TARGETS="${2:-}"; shift 2 ;;
    --allow-read-roots) ALLOW_READ_ROOTS="${2:-}"; shift 2 ;;
    --allow-log-roots) ALLOW_LOG_ROOTS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$HOST" ]] || fail "--host is required"
[[ -n "$ADMIN_USER" ]] || fail "--admin-user is required"

if [[ -z "$ALIAS_RO" ]]; then
  ALIAS_RO="$(safe_alias "$HOST")-ro"
fi
if [[ -z "$ALIAS_ACT" ]]; then
  ALIAS_ACT="$(safe_alias "$HOST")-act"
fi
if [[ -z "$ROLE" ]]; then
  ROLE="Managed Linux node"
fi

cat <<'INTRO'
# Copy/paste these commands in a terminal on the OpenClaw host.
# They create local SSH keys if needed, copy agentictl to the node,
# run the node installer through an existing admin SSH account,
# then register and verify the node locally.

INTRO

printf 'NODE_HOST=%s\n' "$(sq "$HOST")"
printf 'ADMIN_USER=%s\n' "$(sq "$ADMIN_USER")"
printf 'NODE_RO=%s\n' "$(sq "$ALIAS_RO")"
if [[ "$READONLY_ONLY" != "true" ]]; then
  printf 'NODE_ACT=%s\n' "$(sq "$ALIAS_ACT")"
fi
printf 'ROLE=%s\n' "$(sq "$ROLE")"
printf 'TARBALL=%s\n' "$(sq "$TARBALL")"
printf 'RO_KEY=%s\n' "$(sq "$READONLY_KEY")"
if [[ "$READONLY_ONLY" != "true" ]]; then
  printf 'ACT_KEY=%s\n' "$(sq "$ACTION_KEY")"
fi

cat <<'LOCAL_SETUP'

test -f "$RO_KEY" || ssh-keygen -t ed25519 -N '' -f "$RO_KEY" -C agentictl-ro
LOCAL_SETUP
if [[ "$READONLY_ONLY" != "true" ]]; then
  cat <<'ACTION_KEYGEN'
test -f "$ACT_KEY" || ssh-keygen -t ed25519 -N '' -f "$ACT_KEY" -C agentictl-act
ACTION_KEYGEN
fi

if [[ "$READONLY_ONLY" == "true" ]]; then
  cat <<'COPY_RO'

scp "$TARBALL" "$ADMIN_USER@$NODE_HOST:/tmp/agentictl-0.1.0.tar.gz"
scp "$RO_KEY.pub" "$ADMIN_USER@$NODE_HOST:/tmp/agentictl_ro.pub"
COPY_RO
else
  cat <<'COPY_BOTH'

scp "$TARBALL" "$ADMIN_USER@$NODE_HOST:/tmp/agentictl-0.1.0.tar.gz"
scp "$RO_KEY.pub" "$ADMIN_USER@$NODE_HOST:/tmp/agentictl_ro.pub"
scp "$ACT_KEY.pub" "$ADMIN_USER@$NODE_HOST:/tmp/agentictl_act.pub"
COPY_BOTH
fi

cat <<'REMOTE_HEAD'

ssh "$ADMIN_USER@$NODE_HOST" 'bash -s' <<'AGENTICTL_REMOTE_INSTALL'
set -euo pipefail
cd /tmp
rm -rf agentictl-0.1.0
tar -xzf agentictl-0.1.0.tar.gz
cd agentictl-0.1.0
sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file /tmp/agentictl_ro.pub \
REMOTE_HEAD

if [[ "$READONLY_ONLY" != "true" ]]; then
  printf '  --action-public-key-file /tmp/agentictl_act.pub \\\n'
fi
if [[ -n "$READONLY_EXTRA_GROUPS" ]]; then
  printf '  --readonly-extra-groups %s \\\n' "$(sq "$READONLY_EXTRA_GROUPS")"
fi
printf '  --allow-service-restart %s \\\n' "$(sq "$ALLOW_SERVICE_RESTART")"
printf '  --allow-package-install %s \\\n' "$(sq "$ALLOW_PACKAGE_INSTALL")"
printf '  --allow-config-targets %s \\\n' "$(sq "$ALLOW_CONFIG_TARGETS")"
printf '  --allow-read-roots %s \\\n' "$(sq "$ALLOW_READ_ROOTS")"
printf '  --allow-log-roots %s\n' "$(sq "$ALLOW_LOG_ROOTS")"
cat <<'REMOTE_TAIL'
AGENTICTL_REMOTE_INSTALL

agentictl-node-tool.sh add --alias "$NODE_RO" --host "$NODE_HOST" --user agentictl-ro --mode readonly --identity "$RO_KEY" --role "$ROLE"
agentictl-node-tool.sh role-set --node "$NODE_RO" --source user --description "$ROLE"
agentictl-ssh-tool.sh --target "$NODE_RO" --record-kind capabilities -- capabilities
agentictl-ssh-tool.sh --target "$NODE_RO" --record-kind health -- health
agentictl-ssh-tool.sh --target "$NODE_RO" --record-kind packages -- package-list --limit 5000
agentictl-ssh-tool.sh --target "$NODE_RO" --record-kind kernel-modules -- kernel-modules --limit 2000
REMOTE_TAIL

if [[ "$READONLY_ONLY" != "true" ]]; then
  cat <<'ACTION_REGISTER'
agentictl-node-tool.sh add --alias "$NODE_ACT" --host "$NODE_HOST" --user agentictl-act --mode act --identity "$ACT_KEY"
agentictl-ssh-tool.sh --target "$NODE_ACT" -- package-install --name htop --dry-run
ACTION_REGISTER
fi
