#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
NODE_TOOL="$SCRIPT_DIR/agentictl-node-tool.sh"
SAFE_ID_REGEX='^[A-Za-z0-9_.@:-]+$'
TOKEN_REGEX='^[A-Za-z0-9_./@:+,=-]+$'

usage() {
  cat <<'USAGE'
{"ok":false,"error":"usage: agentictl-ssh-tool.sh --target NODE [--record-kind KIND] [--allow-execute] [--stdin-file PATH] -- COMMAND [ARGS...]"}
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
  local code="$1"; shift
  printf '{"ok":false,"error":%s}\n' "$(json_string "$*")" >&2
  exit "$code"
}

validate_id() {
  local value="$1" name="$2"
  [[ "$value" =~ $SAFE_ID_REGEX ]] || fail 65 "invalid $name"
}

validate_token() {
  local token="$1"
  [[ -n "$token" ]] || fail 65 "empty token is not allowed"
  [[ "$token" =~ $TOKEN_REGEX ]] || fail 65 "unsafe token: $token"
  [[ "$token" != *".."* ]] || fail 65 "parent-directory references are not allowed"
}

inventory_file() {
  printf '%s' "${AGENTICTL_NODES_FILE:-${AGENTICTL_WORKSPACE_DIR:-$PWD}/inventory/agentictl-nodes.tsv}"
}

load_target_from_inventory() {
  local alias="$1" inv host user mode identity
  inv="$(inventory_file)"
  [[ -f "$inv" ]] || return 1
  while IFS=$'\t' read -r item_alias host user mode identity _tags; do
    [[ "$item_alias" == "$alias" ]] || continue
    if [[ -z "${user:-}" ]]; then
      if [[ "${mode:-readonly}" == "act" ]]; then
        user="agentictl-act"
      else
        user="agentictl-ro"
      fi
    fi
    SSH_TARGET="${user}@${host:-$alias}"
    if [[ -n "${identity:-}" ]]; then
      SSH_ARGS+=(-i "$identity")
    fi
    return 0
  done < "$inv"
  return 1
}

target=""
record_kind=""
source=""
allow_execute="false"
stdin_file=""
SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=5)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --record-kind) record_kind="${2:-}"; shift 2 ;;
    --source) source="${2:-}"; shift 2 ;;
    --allow-execute) allow_execute="true"; shift ;;
    --stdin-file) stdin_file="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -h|--help) usage; exit 0 ;;
    *) fail 64 "unknown argument before --: $1" ;;
  esac
done

[[ -n "$target" ]] || fail 65 "--target is required"
validate_id "$target" "--target"
[[ -z "$record_kind" || "$record_kind" =~ $SAFE_ID_REGEX ]] || fail 65 "invalid --record-kind"
[[ "$source" != *$'\t'* ]] || fail 65 "tabs are not allowed in --source"
[[ -z "$stdin_file" || -r "$stdin_file" ]] || fail 66 "stdin file not readable"
[[ $# -gt 0 ]] || fail 65 "missing command after --"

cmd_text=""
for token in "$@"; do
  validate_token "$token"
  cmd_text="${cmd_text:+$cmd_text }$token"
  if [[ "$token" == "--execute" && "$allow_execute" != "true" ]]; then
    fail 67 "--execute requires --allow-execute"
  fi
done

SSH_TARGET="$target"
load_target_from_inventory "$target" || true

if [[ -z "$source" ]]; then
  source="ssh $target $cmd_text"
fi

set +e
if [[ -n "$stdin_file" ]]; then
  output="$(ssh "${SSH_ARGS[@]}" "$SSH_TARGET" "$@" < "$stdin_file" 2>&1)"
else
  output="$(ssh "${SSH_ARGS[@]}" "$SSH_TARGET" "$@" 2>&1)"
fi
status=$?
set -e

printf '%s\n' "$output"
if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

if [[ -n "$record_kind" ]]; then
  printf '%s\n' "$output" | bash "$NODE_TOOL" record --node "$target" --kind "$record_kind" --source "$source" >/dev/null
fi
