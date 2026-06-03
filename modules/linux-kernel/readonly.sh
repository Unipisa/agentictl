agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    readonly:dmesg)
      need_cmd dmesg
      local level="err,warn" lines="500"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --level) level="${2:-}"; shift 2 ;;
          --lines) lines="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$level" =~ ^(emerg|alert|crit|err|warn|notice|info|debug)(,(emerg|alert|crit|err|warn|notice|info|debug))*$ ]] || fail 65 "invalid dmesg level"
      validate_lines "$lines"
      dmesg --level "$level" --ctime | tail -n "$lines"
      ;;

    readonly:kernel-modules)
      local limit="1000" count comma name size used_by deps state address _rest
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --limit) limit="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      validate_positive_int "$limit" "--limit" "$MAX_MODULE_LIMIT"
      [[ -r /proc/modules ]] || fail 66 "/proc/modules not readable"
      printf '{"ok":true,"source":"/proc/modules","limit":%s,"modules":[' "$limit"
      count=0
      comma=""
      while read -r name size used_by deps state address _rest; do
        [[ -n "${name:-}" ]] || continue
        printf '%s{"name":%s,"size":%s,"used_by":%s,"deps":%s,"state":%s}' \
          "$comma" \
          "$(json_string "$name")" \
          "${size:-0}" \
          "${used_by:-0}" \
          "$(json_string "${deps:-}")" \
          "$(json_string "${state:-}")"
        comma=","
        count=$((count + 1))
        (( count >= limit )) && break
      done < <(sort /proc/modules)
      printf '],"truncated":%s}\n' "$([[ "$count" -ge "$limit" ]] && printf true || printf false)"
      ;;

    *)
      fail 64 "linux.kernel cannot handle $mode:$cmd"
      ;;
  esac
}
