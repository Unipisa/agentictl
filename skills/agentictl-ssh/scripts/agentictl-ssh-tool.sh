#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "agentictl-ssh-tool.sh requires bash; run: bash $0 ..." >&2
  exit 2
fi
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
NODE_TOOL="$SCRIPT_DIR/agentictl-node-tool.sh"
SAFE_ID_REGEX='^[A-Za-z0-9_.@:-]+$'
TOKEN_REGEX='^[A-Za-z0-9_./@:+,=-]+$'

usage() {
  cat <<'USAGE'
{"ok":false,"error":"usage: agentictl-ssh-tool.sh --target NODE [--record-kind KIND] [--approval-id ID] [--stdin-file PATH] -- COMMAND [ARGS...]"}
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

approval_dir() {
  printf '%s' "${AGENTICTL_APPROVAL_DIR:-${AGENTICTL_WORKSPACE_DIR:-$PWD}/state/approvals}"
}

approval_file() {
  local approval_id="$1"
  validate_id "$approval_id" "--approval-id"
  printf '%s/%s.tsv' "$(approval_dir)" "$approval_id"
}

hash_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  else
    cksum | awk '{print $1}'
  fi
}

fingerprint_for_command() {
  local command_text="$1"
  printf 'agentictl-approval-v1\ncommand\t%s\n' "$command_text" | hash_text
}

get_plan_field() {
  local file="$1" key="$2"
  awk -F '\t' -v key="$key" '$1 == key { print $2; found=1; exit } END { exit found ? 0 : 1 }' "$file"
}

require_approval() {
  local approval_id="$1" target_alias="$2" command_text="$3"
  local file status now expires expected actual target_status
  [[ -n "$approval_id" ]] || fail 67 "--execute requires --approval-id from an approved batch plan"
  file="$(approval_file "$approval_id")"
  [[ -f "$file" ]] || fail 66 "approval plan not found: $approval_id"
  status="$(get_plan_field "$file" status || true)"
  [[ "$status" == "approved" ]] || fail 68 "approval plan is not approved: $approval_id"
  now="$(date -u +%s)"
  expires="$(get_plan_field "$file" expires_epoch || true)"
  [[ "$expires" =~ ^[0-9]+$ ]] || fail 66 "approval plan has invalid expiry"
  [[ "$now" -le "$expires" ]] || fail 68 "approval plan expired: $approval_id"
  expected="$(get_plan_field "$file" fingerprint || true)"
  actual="$(fingerprint_for_command "$command_text")"
  [[ "$expected" == "$actual" ]] || fail 68 "command does not match approved plan"
  target_status="$(awk -F '\t' -v target="$target_alias" '$1 == "target" && $2 == target { print $3; found=1; exit } END { exit found ? 0 : 1 }' "$file" || true)"
  [[ "$target_status" == "pending" ]] || fail 68 "target is not pending in approved plan: $target_alias"
}

consume_approval_target() {
  local approval_id="$1" target_alias="$2" file tmp
  file="$(approval_file "$approval_id")"
  tmp="$file.tmp.$$"
  awk -F '\t' -v OFS='\t' -v target="$target_alias" '
    $1 == "target" && $2 == target && $3 == "pending" { $3 = "done" }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
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
approval_id=""
stdin_file=""
SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=5)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --record-kind) record_kind="${2:-}"; shift 2 ;;
    --source) source="${2:-}"; shift 2 ;;
    --allow-execute) allow_execute="true"; shift ;;
    --approval-id) approval_id="${2:-}"; shift 2 ;;
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
cmd_base_text=""
has_execute="false"
has_dry_run="false"
for token in "$@"; do
  validate_token "$token"
  cmd_text="${cmd_text:+$cmd_text }$token"
  case "$token" in
    --execute)
      has_execute="true"
      ;;
    --dry-run)
      has_dry_run="true"
      ;;
    *)
      cmd_base_text="${cmd_base_text:+$cmd_base_text }$token"
      ;;
  esac
done

[[ ! ("$has_execute" == "true" && "$has_dry_run" == "true") ]] || fail 65 "command cannot include both --dry-run and --execute"

if [[ "$has_execute" == "true" ]]; then
  if [[ "$allow_execute" == "true" && -z "$approval_id" ]]; then
    fail 67 "--allow-execute is deprecated for skill execution; use --approval-id from agentictl-approval-tool.sh"
  fi
  require_approval "$approval_id" "$target" "$cmd_base_text"
fi

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

if [[ "$has_execute" == "true" ]]; then
  consume_approval_target "$approval_id" "$target"
fi

if [[ -n "$record_kind" ]]; then
  printf '%s\n' "$output" | bash "$NODE_TOOL" record --node "$target" --kind "$record_kind" --source "$source" >/dev/null
fi
