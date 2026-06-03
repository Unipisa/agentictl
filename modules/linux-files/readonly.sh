agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  load_policy_optional
  case "$mode:$cmd" in
    readonly:fs-list)
      need_cmd find
      need_cmd sort
      need_cmd stat
      local path="" max_depth="1" limit="200" resolved count comma entry
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --path) path="${2:-}"; shift 2 ;;
          --max-depth) max_depth="${2:-}"; shift 2 ;;
          --limit) limit="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ -n "$path" ]] || fail 65 "--path is required"
      validate_positive_int "$max_depth" "--max-depth" "$AGENTICTL_MAX_LIST_DEPTH"
      validate_positive_int "$limit" "--limit" "$AGENTICTL_MAX_LIST_ENTRIES"
      resolved="$(resolve_existing_path "$path")"
      [[ -d "$resolved" ]] || fail 65 "fs-list requires a directory"
      require_read_allowed "$resolved" "$ALLOW_READ_ROOTS"
      printf '{"ok":true,"path":%s,"max_depth":%s,"limit":%s,"entries":[' "$(json_string "$resolved")" "$max_depth" "$limit"
      count=0
      comma=""
      while IFS= read -r -d '' entry; do
        if ! is_under_one_root "$entry" "$ALLOW_READ_ROOTS"; then
          continue
        fi
        if is_denied_path "$entry"; then
          continue
        fi
        print_stat_json "$entry" "$comma"
        comma=","
        count=$((count + 1))
        (( count >= limit )) && break
      done < <(find "$resolved" -maxdepth "$max_depth" -mindepth 1 -print0 2>/dev/null | sort -z)
      printf '],"truncated":%s}\n' "$([[ "$count" -ge "$limit" ]] && printf true || printf false)"
      ;;

    readonly:fs-stat)
      need_cmd stat
      local path="" resolved
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --path) path="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ -n "$path" ]] || fail 65 "--path is required"
      resolved="$(resolve_existing_path "$path")"
      require_read_allowed "$resolved" "$ALLOW_READ_ROOTS"
      printf '{"ok":true,"entry":'
      print_stat_json "$resolved"
      printf '}\n'
      ;;

    readonly:fs-read)
      local path="" tail_lines="" max_bytes="$AGENTICTL_MAX_READ_BYTES" resolved content
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --path) path="${2:-}"; shift 2 ;;
          --tail) tail_lines="${2:-}"; shift 2 ;;
          --max-bytes) max_bytes="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ -n "$path" ]] || fail 65 "--path is required"
      validate_positive_int "$max_bytes" "--max-bytes" "$AGENTICTL_MAX_READ_BYTES"
      [[ -z "$tail_lines" ]] || validate_positive_int "$tail_lines" "--tail" "$MAX_LINES"
      resolved="$(resolve_existing_path "$path")"
      [[ -f "$resolved" ]] || fail 65 "fs-read requires a regular file"
      require_read_allowed "$resolved" "$ALLOW_READ_ROOTS"
      content="$(read_file_limited "$resolved" "$tail_lines" "$max_bytes")"
      printf '{"ok":true,"path":%s,"bytes":%s,"content":%s}\n' \
        "$(json_string "$resolved")" \
        "$(printf '%s' "$content" | wc -c | tr -d ' ')" \
        "$(json_string "$content")"
      ;;

    readonly:log-read)
      local path="" tail_lines="200" max_bytes="$AGENTICTL_MAX_READ_BYTES" resolved content
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --path) path="${2:-}"; shift 2 ;;
          --tail) tail_lines="${2:-}"; shift 2 ;;
          --max-bytes) max_bytes="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ -n "$path" ]] || fail 65 "--path is required"
      validate_positive_int "$tail_lines" "--tail" "$MAX_LINES"
      validate_positive_int "$max_bytes" "--max-bytes" "$AGENTICTL_MAX_READ_BYTES"
      resolved="$(resolve_existing_path "$path")"
      [[ -f "$resolved" ]] || fail 65 "log-read requires a regular file"
      require_read_allowed "$resolved" "$ALLOW_LOG_ROOTS"
      content="$(read_file_limited "$resolved" "$tail_lines" "$max_bytes")"
      printf '{"ok":true,"path":%s,"tail":%s,"bytes":%s,"content":%s}\n' \
        "$(json_string "$resolved")" \
        "$tail_lines" \
        "$(printf '%s' "$content" | wc -c | tr -d ' ')" \
        "$(json_string "$content")"
      ;;

    *)
      fail 64 "linux.files cannot handle $mode:$cmd"
      ;;
  esac
}
