#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "agentictl-approval-tool.sh requires bash; run: bash $0 ..." >&2
  exit 2
fi
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SSH_TOOL="$SCRIPT_DIR/agentictl-ssh-tool.sh"
SAFE_ID_REGEX='^[A-Za-z0-9_.@:-]+$'
TOKEN_REGEX='^[A-Za-z0-9_./@:+,=-]+$'

usage() {
  cat <<'USAGE'
{"ok":false,"error":"usage: agentictl-approval-tool.sh {plan|show|dry-run|approve|execute|revoke} ..."}
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

plan_file() {
  local plan_id="$1"
  validate_id "$plan_id" "--plan-id"
  printf '%s/%s.tsv' "$(approval_dir)" "$plan_id"
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

join_command() {
  local token command_text=""
  [[ $# -gt 0 ]] || fail 65 "missing command after --"
  for token in "$@"; do
    validate_token "$token"
    [[ "$token" != "--execute" && "$token" != "--dry-run" ]] || fail 65 "approval plans store the base command without --dry-run or --execute"
    command_text="${command_text:+$command_text }$token"
  done
  printf '%s' "$command_text"
}

json_targets_from_args() {
  local comma="" target
  printf '['
  for target in "$@"; do
    printf '%s%s' "$comma" "$(json_string "$target")"
    comma=","
  done
  printf ']'
}

get_field() {
  local file="$1" key="$2"
  awk -F '\t' -v key="$key" '$1 == key { print $2; found=1; exit } END { exit found ? 0 : 1 }' "$file"
}

set_field() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$file.tmp.$$"
  awk -F '\t' -v OFS='\t' -v key="$key" -v value="$value" '
    $1 == key { $2 = value; found = 1 }
    { print }
    END { if (!found) print key, value }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

require_plan_file() {
  local file="$1"
  [[ -f "$file" ]] || fail 66 "approval plan not found"
}

ensure_not_expired() {
  local file="$1" now expires
  now="$(date -u +%s)"
  expires="$(get_field "$file" expires_epoch || true)"
  [[ "$expires" =~ ^[0-9]+$ ]] || fail 66 "approval plan has invalid expiry"
  [[ "$now" -le "$expires" ]] || fail 68 "approval plan expired"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  plan)
    targets=()
    ttl_seconds="900"
    requested_plan_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --target) targets+=("${2:-}"); shift 2 ;;
        --ttl-seconds) ttl_seconds="${2:-}"; shift 2 ;;
        --plan-id) requested_plan_id="${2:-}"; shift 2 ;;
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        *) fail 64 "unknown argument before --: $1" ;;
      esac
    done
    [[ "${#targets[@]}" -gt 0 ]] || fail 65 "at least one --target is required"
    [[ "$ttl_seconds" =~ ^[0-9]+$ && "$ttl_seconds" -ge 60 && "$ttl_seconds" -le 86400 ]] || fail 65 "--ttl-seconds must be between 60 and 86400"
    for target in "${targets[@]}"; do
      validate_id "$target" "--target"
    done
    command_text="$(join_command "$@")"
    fingerprint="$(fingerprint_for_command "$command_text")"
    created_epoch="$(date -u +%s)"
    expires_epoch=$((created_epoch + ttl_seconds))
    if [[ -n "$requested_plan_id" ]]; then
      plan_id="$requested_plan_id"
      validate_id "$plan_id" "--plan-id"
    else
      plan_id="approval-$(date -u +%Y%m%dT%H%M%SZ)-${fingerprint:0:12}-$$"
    fi
    file="$(plan_file "$plan_id")"
    [[ ! -e "$file" ]] || fail 77 "approval plan already exists: $plan_id"
    mkdir -p "$(dirname "$file")"
    {
      printf 'version\t1\n'
      printf 'status\tpending\n'
      printf 'created_epoch\t%s\n' "$created_epoch"
      printf 'expires_epoch\t%s\n' "$expires_epoch"
      printf 'command\t%s\n' "$command_text"
      printf 'fingerprint\t%s\n' "$fingerprint"
      for target in "${targets[@]}"; do
        printf 'target\t%s\tpending\n' "$target"
      done
    } > "$file"
    printf '{"ok":true,"action":"plan","plan_id":%s,"status":"pending","command":%s,"targets":%s,"expires_epoch":%s,"dry_run_command":%s,"approve_command":%s,"execute_command":%s}\n' \
      "$(json_string "$plan_id")" \
      "$(json_string "$command_text")" \
      "$(json_targets_from_args "${targets[@]}")" \
      "$expires_epoch" \
      "$(json_string "agentictl-approval-tool.sh dry-run --plan-id $plan_id")" \
      "$(json_string "agentictl-approval-tool.sh approve --plan-id $plan_id")" \
      "$(json_string "agentictl-approval-tool.sh execute --plan-id $plan_id")"
    ;;

  show)
    plan_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --plan-id) plan_id="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail 64 "unknown argument: $1" ;;
      esac
    done
    [[ -n "$plan_id" ]] || fail 65 "--plan-id is required"
    file="$(plan_file "$plan_id")"
    require_plan_file "$file"
    status="$(get_field "$file" status)"
    command_text="$(get_field "$file" command)"
    expires_epoch="$(get_field "$file" expires_epoch)"
    printf '{"ok":true,"plan_id":%s,"status":%s,"command":%s,"expires_epoch":%s,"targets":[' \
      "$(json_string "$plan_id")" \
      "$(json_string "$status")" \
      "$(json_string "$command_text")" \
      "$expires_epoch"
    comma=""
    while IFS=$'\t' read -r key target target_status; do
      [[ "$key" == "target" ]] || continue
      printf '%s{"target":%s,"status":%s}' "$comma" "$(json_string "$target")" "$(json_string "$target_status")"
      comma=","
    done < "$file"
    printf ']}\n'
    ;;

  dry-run|execute)
    plan_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --plan-id) plan_id="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail 64 "unknown argument: $1" ;;
      esac
    done
    [[ -n "$plan_id" ]] || fail 65 "--plan-id is required"
    file="$(plan_file "$plan_id")"
    require_plan_file "$file"
    ensure_not_expired "$file"
    status="$(get_field "$file" status)"
    command_text="$(get_field "$file" command)"
    if [[ "$cmd" == "execute" ]]; then
      [[ "$status" == "approved" ]] || fail 68 "approval plan is not approved"
      phase_flag="--execute"
    else
      [[ "$status" != "revoked" ]] || fail 68 "approval plan is revoked"
      phase_flag="--dry-run"
    fi
    local_ifs="$IFS"
    IFS=' ' read -r -a command_args <<< "$command_text"
    IFS="$local_ifs"
    ran_any="false"
    while IFS=$'\t' read -r key target target_status; do
      [[ "$key" == "target" ]] || continue
      if [[ "$cmd" == "execute" && "$target_status" != "pending" ]]; then
        continue
      fi
      ran_any="true"
      printf '{"ok":true,"plan_id":%s,"phase":%s,"target":%s}\n' \
        "$(json_string "$plan_id")" \
        "$(json_string "$cmd")" \
        "$(json_string "$target")"
      if [[ "$cmd" == "execute" ]]; then
        bash "$SSH_TOOL" --target "$target" --approval-id "$plan_id" -- "${command_args[@]}" "$phase_flag"
      else
        bash "$SSH_TOOL" --target "$target" -- "${command_args[@]}" "$phase_flag"
      fi
    done < "$file"
    if [[ "$ran_any" == "false" ]]; then
      printf '{"ok":true,"plan_id":%s,"phase":%s,"message":"no pending targets"}\n' \
        "$(json_string "$plan_id")" \
        "$(json_string "$cmd")"
    fi
    ;;

  approve)
    plan_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --plan-id) plan_id="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail 64 "unknown argument: $1" ;;
      esac
    done
    [[ -n "$plan_id" ]] || fail 65 "--plan-id is required"
    file="$(plan_file "$plan_id")"
    require_plan_file "$file"
    ensure_not_expired "$file"
    status="$(get_field "$file" status)"
    [[ "$status" == "pending" ]] || fail 68 "only pending plans can be approved"
    [[ -t 0 ]] || fail 68 "approval requires an interactive terminal; do not approve from chat output"
    command_text="$(get_field "$file" command)"
    phrase="APPROVE $plan_id"
    {
      printf 'agentictl approval plan: %s\n' "$plan_id"
      printf 'command: %s\n' "$command_text"
      printf 'targets:\n'
      awk -F '\t' '$1 == "target" { printf "  - %s (%s)\n", $2, $3 }' "$file"
      printf 'type exactly: %s\n' "$phrase"
    } >&2
    read -r entered
    [[ "$entered" == "$phrase" ]] || fail 68 "approval phrase mismatch"
    set_field "$file" status approved
    set_field "$file" approved_epoch "$(date -u +%s)"
    printf '{"ok":true,"action":"approve","plan_id":%s,"status":"approved"}\n' "$(json_string "$plan_id")"
    ;;

  revoke)
    plan_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --plan-id) plan_id="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail 64 "unknown argument: $1" ;;
      esac
    done
    [[ -n "$plan_id" ]] || fail 65 "--plan-id is required"
    file="$(plan_file "$plan_id")"
    require_plan_file "$file"
    set_field "$file" status revoked
    printf '{"ok":true,"action":"revoke","plan_id":%s,"status":"revoked"}\n' "$(json_string "$plan_id")"
    ;;

  *)
    usage
    exit 64
    ;;
esac
