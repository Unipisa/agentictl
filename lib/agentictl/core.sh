#!/usr/bin/env bash

BASE_DIR="${AGENTICTL_BASE_DIR:-${OPENCLAW_BASE_DIR:-/opt/agentictl}}"
POLICY_FILE="${AGENTICTL_POLICY_FILE:-${OPENCLAW_POLICY_FILE:-$BASE_DIR/config/policy.env}}"
AUDIT_LOG="${AGENTICTL_AUDIT_LOG:-${OPENCLAW_AUDIT_LOG:-$BASE_DIR/state/audit.log}}"
BACKUP_DIR="${AGENTICTL_BACKUP_DIR:-${OPENCLAW_BACKUP_DIR:-$BASE_DIR/state/backups}}"
STAGING_DIR="${AGENTICTL_STAGING_DIR:-${OPENCLAW_STAGING_DIR:-$BASE_DIR/state/incoming}}"
MAX_ORIGINAL_COMMAND_BYTES="${AGENTICTL_MAX_ORIGINAL_COMMAND_BYTES:-${OPENCLAW_MAX_ORIGINAL_COMMAND_BYTES:-4096}}"

ALLOWED_UNITS_REGEX='^[a-zA-Z0-9_.@-]+\.service$'
ALLOWED_PACKAGES_REGEX='^[a-zA-Z0-9_.+:-]+$'
SAFE_STAGE_NAME_REGEX='^[a-zA-Z0-9_.@-]+$'
TOKEN_REGEX='^[A-Za-z0-9_./@:+,=-]+$'

MAX_LINES=2000
MAX_PACKAGE_LIMIT=10000
MAX_MODULE_LIMIT=4096
DEFAULT_ALLOW_READ_ROOTS="/var/log /etc"
DEFAULT_ALLOW_LOG_ROOTS="/var/log"
DEFAULT_DENY_READ_PATHS="/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"
DEFAULT_MAX_READ_BYTES=262144
DEFAULT_MAX_LIST_ENTRIES=2000
DEFAULT_MAX_LIST_DEPTH=5
DEFAULT_MAX_CONFIG_BYTES=1048576

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
  printf '{"ok":false,"error":%s}\n' "$(json_string "$*")"
  exit "$code"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail 70 "missing command: $1"
}

contains_word() {
  local needle="$1"; shift
  local haystack=" $* "
  [[ "$haystack" == *" $needle "* ]]
}

validate_since() {
  [[ "${1:-}" =~ ^[0-9]+(m|h|d)$ ]] || fail 65 "invalid --since, use e.g. 30m, 2h, 1d"
}

validate_lines() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || fail 65 "invalid --lines"
  (( "$1" >= 1 && "$1" <= MAX_LINES )) || fail 65 "--lines out of range"
}

validate_positive_int() {
  local value="$1" name="$2" max="$3"
  [[ "$value" =~ ^[0-9]+$ ]] || fail 65 "invalid $name"
  (( value >= 1 && value <= max )) || fail 65 "$name out of range"
}

trim_spaces() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_policy_optional() {
  if [[ -r "$POLICY_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$POLICY_FILE"
  fi
  : "${ALLOW_READ_ROOTS:=$DEFAULT_ALLOW_READ_ROOTS}"
  : "${ALLOW_LOG_ROOTS:=$DEFAULT_ALLOW_LOG_ROOTS}"
  : "${DENY_READ_PATHS:=$DEFAULT_DENY_READ_PATHS}"
  : "${AGENTICTL_MAX_READ_BYTES:=$DEFAULT_MAX_READ_BYTES}"
  : "${AGENTICTL_MAX_LIST_ENTRIES:=$DEFAULT_MAX_LIST_ENTRIES}"
  : "${AGENTICTL_MAX_LIST_DEPTH:=$DEFAULT_MAX_LIST_DEPTH}"
}

load_policy_required() {
  [[ -r "$POLICY_FILE" ]] || fail 66 "missing policy file: $POLICY_FILE"
  # shellcheck source=/dev/null
  source "$POLICY_FILE"
  : "${ALLOW_SERVICE_RESTART:=}"
  : "${ALLOW_PACKAGE_INSTALL:=}"
  : "${ALLOW_PACKAGE_UPGRADE:=}"
  : "${ALLOW_PACKAGE_UPGRADE_ALL:=false}"
  : "${ALLOW_CONFIG_TARGETS:=}"
  : "${AGENTICTL_MAX_CONFIG_BYTES:=${OPENCLAW_MAX_CONFIG_BYTES:-$DEFAULT_MAX_CONFIG_BYTES}}"
}

audit_event() {
  local event="${1:-unknown}" detail="${2:-}" result="${3:-}"
  local audit_dir
  audit_dir="$(dirname "$AUDIT_LOG")"
  mkdir -p "$audit_dir" 2>/dev/null || return 0
  [[ -e "$AUDIT_LOG" && -w "$AUDIT_LOG" ]] || [[ ! -e "$AUDIT_LOG" && -w "$audit_dir" ]] || return 0
  printf '{"ts":%s,"actor":%s,"event":%s,"detail":%s,"result":%s}\n' \
    "$(json_string "$(date --iso-8601=seconds 2>/dev/null || date)")" \
    "$(json_string "${USER:-unknown}")" \
    "$(json_string "$event")" \
    "$(json_string "$detail")" \
    "$(json_string "$result")" >> "$AUDIT_LOG" 2>/dev/null || true
}

audit_action() {
  local action="$1" target="$2" mode="$3" result="$4"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  printf '{"ts":%s,"actor":%s,"action":%s,"target":%s,"mode":%s,"result":%s}\n' \
    "$(json_string "$(date --iso-8601=seconds 2>/dev/null || date)")" \
    "$(json_string "${USER:-unknown}")" \
    "$(json_string "$action")" \
    "$(json_string "$target")" \
    "$(json_string "$mode")" \
    "$(json_string "$result")" >> "$AUDIT_LOG"
}

resolve_existing_path() {
  local path="$1"
  [[ "$path" = /* ]] || fail 65 "path must be absolute"
  [[ "$path" != *".."* ]] || fail 65 "parent-directory references are not allowed"
  need_cmd readlink
  readlink -f "$path" 2>/dev/null || fail 66 "path not found: $path"
}

is_under_one_root() {
  local resolved="$1" roots="$2" root root_real
  local old_ifs="$IFS"
  IFS=' '
  for root in $roots; do
    IFS="$old_ifs"
    [[ -n "$root" ]] || { IFS=' '; continue; }
    root_real="$(readlink -f "$root" 2>/dev/null || true)"
    if [[ -n "$root_real" && ( "$resolved" == "$root_real" || "$resolved" == "$root_real"/* ) ]]; then
      IFS="$old_ifs"
      return 0
    fi
    IFS=' '
  done
  IFS="$old_ifs"
  return 1
}

is_denied_path() {
  local resolved="$1" deny_path deny_real
  local old_ifs="$IFS"
  IFS=' '
  for deny_path in $DENY_READ_PATHS; do
    IFS="$old_ifs"
    [[ -n "$deny_path" ]] || { IFS=' '; continue; }
    deny_real="$(readlink -f "$deny_path" 2>/dev/null || true)"
    if [[ -n "$deny_real" && ( "$resolved" == "$deny_real" || "$resolved" == "$deny_real"/* ) ]]; then
      IFS="$old_ifs"
      return 0
    fi
    IFS=' '
  done
  IFS="$old_ifs"
  return 1
}

require_read_allowed() {
  local resolved="$1" roots="${2:-$ALLOW_READ_ROOTS}"
  if ! is_under_one_root "$resolved" "$roots"; then
    fail 77 "path not under allowed read roots"
  fi
  if is_denied_path "$resolved"; then
    fail 77 "path denied by DENY_READ_PATHS"
  fi
}

file_type() {
  local path="$1"
  if [[ -d "$path" ]]; then printf 'directory'
  elif [[ -f "$path" ]]; then printf 'file'
  elif [[ -L "$path" ]]; then printf 'symlink'
  else printf 'other'
  fi
}

print_stat_json() {
  local path="$1" comma="${2:-}"
  local type size mode owner group mtime
  type="$(file_type "$path")"
  size="$(stat -c '%s' "$path")"
  mode="$(stat -c '%a' "$path")"
  owner="$(stat -c '%U' "$path")"
  group="$(stat -c '%G' "$path")"
  mtime="$(stat -c '%Y' "$path")"
  printf '%s{"path":%s,"type":%s,"size":%s,"mode":%s,"owner":%s,"group":%s,"mtime":%s}' \
    "$comma" \
    "$(json_string "$path")" \
    "$(json_string "$type")" \
    "$size" \
    "$(json_string "$mode")" \
    "$(json_string "$owner")" \
    "$(json_string "$group")" \
    "$mtime"
}

read_file_limited() {
  local path="$1" tail_lines="$2" max_bytes="$3" content
  if [[ -n "$tail_lines" ]]; then
    content="$(tail -n "$tail_lines" "$path" | head -c "$max_bytes")"
  else
    content="$(head -c "$max_bytes" "$path")"
  fi
  printf '%s' "$content"
}

maybe_reexec_with_sudo() {
  [[ "${AGENTICTL_ACT_SUDO:-${OPENCLAW_ACT_SUDO:-auto}}" != "never" ]] || return 0
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || return 0

  local arg wants_execute="false"
  for arg in "$@"; do
    [[ "$arg" == "--execute" ]] && wants_execute="true"
  done

  [[ "$wants_execute" == "true" ]] || return 0
  command -v sudo >/dev/null 2>&1 || fail 70 "sudo is required for --execute"
  exec sudo -n -- "$0" "$@"
}

require_execute_flag() {
  [[ "${EXECUTE:-false}" == "true" ]] || fail 67 "refusing to act without --execute; use --dry-run to preview"
}

declare -ga AGENTICTL_MODULE_IDS=()
declare -gA AGENTICTL_MODULE_LABELS=()
declare -gA AGENTICTL_MODULE_READONLY_VERBS=()
declare -gA AGENTICTL_MODULE_ACT_VERBS=()
declare -gA AGENTICTL_MODULE_SEEN=()
declare -gA AGENTICTL_READONLY_VERB_HANDLER=()
declare -gA AGENTICTL_READONLY_VERB_MODULE=()
declare -gA AGENTICTL_ACT_VERB_HANDLER=()
declare -gA AGENTICTL_ACT_VERB_MODULE=()
AGENTICTL_MODULES_LOADED="false"

agentictl_default_module_path() {
  local script_dir="${AGENTICTL_SCRIPT_DIR:-}"
  if [[ -n "$script_dir" && -d "$script_dir/../modules" ]]; then
    cd -- "$script_dir/../modules" && pwd
  else
    printf '%s/modules' "$BASE_DIR"
  fi
}

agentictl_validate_module_id() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_.-]*$ ]] || fail 78 "invalid module id: ${1:-}"
}

agentictl_validate_verb() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9-]*$ ]] || fail 78 "invalid module verb: ${1:-}"
}

agentictl_register_module_verbs() {
  local module_id="$1" mode="$2" verbs="$3" handler="$4" verb
  [[ -z "$verbs" ]] && return 0
  [[ -r "$handler" ]] || fail 78 "module handler not readable: $handler"

  local old_ifs="$IFS"
  IFS=' '
  for verb in $verbs; do
    IFS="$old_ifs"
    [[ -n "$verb" ]] || { IFS=' '; continue; }
    agentictl_validate_verb "$verb"
    case "$mode" in
      readonly)
        [[ -z "${AGENTICTL_READONLY_VERB_HANDLER[$verb]:-}" ]] || fail 78 "duplicate readonly verb: $verb"
        AGENTICTL_READONLY_VERB_HANDLER["$verb"]="$handler"
        AGENTICTL_READONLY_VERB_MODULE["$verb"]="$module_id"
        ;;
      act)
        [[ -z "${AGENTICTL_ACT_VERB_HANDLER[$verb]:-}" ]] || fail 78 "duplicate act verb: $verb"
        AGENTICTL_ACT_VERB_HANDLER["$verb"]="$handler"
        AGENTICTL_ACT_VERB_MODULE["$verb"]="$module_id"
        ;;
      *) fail 78 "invalid module mode: $mode" ;;
    esac
    IFS=' '
  done
  IFS="$old_ifs"
}

agentictl_load_module_manifest() {
  local module_dir="$1"
  module_dir="$(cd -- "$module_dir" && pwd)"
  local manifest="$module_dir/module.env"
  [[ -r "$manifest" ]] || return 0

  AGENTICTL_MODULE_ID=""
  AGENTICTL_MODULE_LABEL=""
  AGENTICTL_MODULE_READONLY_VERBS=""
  AGENTICTL_MODULE_ACT_VERBS=""
  AGENTICTL_MODULE_READONLY_HANDLER="$module_dir/readonly.sh"
  AGENTICTL_MODULE_ACT_HANDLER="$module_dir/act.sh"
  AGENTICTL_MODULE_DIR="$module_dir"

  # shellcheck source=/dev/null
  source "$manifest"

  agentictl_validate_module_id "$AGENTICTL_MODULE_ID"
  [[ -z "${AGENTICTL_MODULE_SEEN[$AGENTICTL_MODULE_ID]:-}" ]] || fail 78 "duplicate module id: $AGENTICTL_MODULE_ID"
  AGENTICTL_MODULE_SEEN["$AGENTICTL_MODULE_ID"]="true"
  AGENTICTL_MODULE_LABEL="${AGENTICTL_MODULE_LABEL:-$AGENTICTL_MODULE_ID}"

  if [[ -n "$AGENTICTL_MODULE_READONLY_VERBS" && "$AGENTICTL_MODULE_READONLY_HANDLER" != "$module_dir"/* ]]; then
    fail 78 "readonly handler must stay under module directory: $AGENTICTL_MODULE_ID"
  fi
  if [[ -n "$AGENTICTL_MODULE_ACT_VERBS" && "$AGENTICTL_MODULE_ACT_HANDLER" != "$module_dir"/* ]]; then
    fail 78 "act handler must stay under module directory: $AGENTICTL_MODULE_ID"
  fi

  AGENTICTL_MODULE_IDS+=("$AGENTICTL_MODULE_ID")
  AGENTICTL_MODULE_LABELS["$AGENTICTL_MODULE_ID"]="$AGENTICTL_MODULE_LABEL"
  AGENTICTL_MODULE_READONLY_VERBS["$AGENTICTL_MODULE_ID"]="$AGENTICTL_MODULE_READONLY_VERBS"
  AGENTICTL_MODULE_ACT_VERBS["$AGENTICTL_MODULE_ID"]="$AGENTICTL_MODULE_ACT_VERBS"

  agentictl_register_module_verbs "$AGENTICTL_MODULE_ID" readonly "$AGENTICTL_MODULE_READONLY_VERBS" "$AGENTICTL_MODULE_READONLY_HANDLER"
  agentictl_register_module_verbs "$AGENTICTL_MODULE_ID" act "$AGENTICTL_MODULE_ACT_VERBS" "$AGENTICTL_MODULE_ACT_HANDLER"
}

agentictl_load_modules() {
  [[ "$AGENTICTL_MODULES_LOADED" == "true" ]] && return 0
  local module_path="${AGENTICTL_MODULE_PATH:-$(agentictl_default_module_path)}"
  local root module_dir
  local old_ifs="$IFS"
  shopt -s nullglob
  IFS=':'
  for root in $module_path; do
    IFS="$old_ifs"
    [[ -d "$root" ]] || { IFS=':'; continue; }
    for module_dir in "$root"/*; do
      [[ -d "$module_dir" ]] || continue
      agentictl_load_module_manifest "$module_dir"
    done
    IFS=':'
  done
  IFS="$old_ifs"
  shopt -u nullglob
  AGENTICTL_MODULES_LOADED="true"
}

agentictl_mode_has_verb() {
  local mode="$1" verb="$2"
  case "$verb" in
    capabilities) return 0 ;;
  esac
  case "$mode" in
    readonly) [[ -n "${AGENTICTL_READONLY_VERB_HANDLER[$verb]:-}" ]] ;;
    act) [[ -n "${AGENTICTL_ACT_VERB_HANDLER[$verb]:-}" ]] ;;
    *) return 1 ;;
  esac
}

agentictl_print_json_array_words() {
  local words="$1" include_capabilities="${2:-false}"
  local comma="" word old_ifs
  printf '['
  if [[ "$include_capabilities" == "true" ]]; then
    printf '%s' "$(json_string capabilities)"
    comma=","
  fi
  old_ifs="$IFS"
  IFS=' '
  for word in $words; do
    IFS="$old_ifs"
    [[ -n "$word" ]] || { IFS=' '; continue; }
    printf '%s%s' "$comma" "$(json_string "$word")"
    comma=","
    IFS=' '
  done
  IFS="$old_ifs"
  printf ']'
}

agentictl_mode_verbs() {
  local mode="$1" module_id verbs=""
  for module_id in "${AGENTICTL_MODULE_IDS[@]}"; do
    case "$mode" in
      readonly) verbs="$verbs ${AGENTICTL_MODULE_READONLY_VERBS[$module_id]:-}" ;;
      act) verbs="$verbs ${AGENTICTL_MODULE_ACT_VERBS[$module_id]:-}" ;;
    esac
  done
  printf '%s' "$verbs"
}

agentictl_print_capabilities() {
  local mode="$1"
  local module_id verbs comma=""
  printf '{"ok":true,"mode":%s,"commands":' "$(json_string "$mode")"
  agentictl_print_json_array_words "$(agentictl_mode_verbs "$mode")" true
  printf ',"modules":['
  for module_id in "${AGENTICTL_MODULE_IDS[@]}"; do
    case "$mode" in
      readonly) verbs="${AGENTICTL_MODULE_READONLY_VERBS[$module_id]:-}" ;;
      act) verbs="${AGENTICTL_MODULE_ACT_VERBS[$module_id]:-}" ;;
      *) verbs="" ;;
    esac
    [[ -n "$verbs" ]] || continue
    printf '%s{"id":%s,"label":%s,"verbs":' \
      "$comma" \
      "$(json_string "$module_id")" \
      "$(json_string "${AGENTICTL_MODULE_LABELS[$module_id]:-$module_id}")"
    agentictl_print_json_array_words "$verbs" false
    printf '}'
    comma=","
  done
  printf ']}\n'
}

agentictl_dispatch_module() {
  local mode="$1" cmd="$2"; shift 2
  local handler module_id
  case "$mode" in
    readonly)
      handler="${AGENTICTL_READONLY_VERB_HANDLER[$cmd]:-}"
      module_id="${AGENTICTL_READONLY_VERB_MODULE[$cmd]:-}"
      ;;
    act)
      handler="${AGENTICTL_ACT_VERB_HANDLER[$cmd]:-}"
      module_id="${AGENTICTL_ACT_VERB_MODULE[$cmd]:-}"
      ;;
    *) fail 64 "invalid mode: $mode" ;;
  esac
  [[ -n "$handler" ]] || fail 64 "command not allowed in $mode mode: $cmd"
  unset -f agentictl_module_dispatch 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$handler"
  declare -F agentictl_module_dispatch >/dev/null || fail 78 "module handler missing dispatcher: $module_id"
  agentictl_module_dispatch "$mode" "$cmd" "$@"
}
