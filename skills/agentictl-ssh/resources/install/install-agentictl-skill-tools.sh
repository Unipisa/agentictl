#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BIN_DIR="${HOME:-.}/.local/bin"

usage() {
  cat <<'USAGE'
Usage:
  install-agentictl-skill-tools.sh [--bin-dir PATH]

Installs the local OpenClaw-side agentictl helper scripts from this skill into a user-writable bin directory.
USAGE
}

json_string() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

fail() {
  printf '{"ok":false,"error":%s}\n' "$(json_string "$*")" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin-dir) BIN_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$BIN_DIR" && "$BIN_DIR" = /* ]] || fail "--bin-dir must be an absolute path"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

install -d -m 0755 "$BIN_DIR"
SHARE_DIR="$(cd -- "$BIN_DIR/.." && pwd)/share/agentictl-ssh"
install -d -m 0755 "$SHARE_DIR/resources/dist" "$SHARE_DIR/resources/node"
install -m 0755 "$SKILL_DIR/resources/bin/agentictl-nodes" "$BIN_DIR/agentictl-nodes"
install -m 0755 "$SKILL_DIR/scripts/agentictl-node-tool.sh" "$BIN_DIR/agentictl-node-tool.sh"
install -m 0755 "$SKILL_DIR/scripts/agentictl-ssh-tool.sh" "$BIN_DIR/agentictl-ssh-tool.sh"
install -m 0755 "$SKILL_DIR/scripts/agentictl-bootstrap-instructions.sh" "$BIN_DIR/agentictl-bootstrap-instructions.sh"
install -m 0755 "$SKILL_DIR/scripts/agentictl-node-upgrade.sh" "$BIN_DIR/agentictl-node-upgrade.sh"
install -m 0644 "$SKILL_DIR/resources/dist/agentictl-0.1.0.tar.gz" "$SHARE_DIR/resources/dist/agentictl-0.1.0.tar.gz"
install -m 0644 "$SKILL_DIR/resources/dist/agentictl-0.1.0.manifest" "$SHARE_DIR/resources/dist/agentictl-0.1.0.manifest"
install -m 0755 "$SKILL_DIR/resources/node/install-node.sh" "$SHARE_DIR/resources/node/install-node.sh"

printf '{"ok":true,"bin_dir":%s,"share_dir":%s,"installed":["agentictl-nodes","agentictl-node-tool.sh","agentictl-ssh-tool.sh","agentictl-bootstrap-instructions.sh","agentictl-node-upgrade.sh","resources/dist/agentictl-0.1.0.tar.gz","resources/node/install-node.sh"]}\n' \
  "$(json_string "$BIN_DIR")" \
  "$(json_string "$SHARE_DIR")"
