agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    readonly:journal)
      need_cmd journalctl
      local unit="" since="30m" lines="500"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --unit) unit="${2:-}"; shift 2 ;;
          --since) since="${2:-}"; shift 2 ;;
          --lines) lines="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$unit" =~ $ALLOWED_UNITS_REGEX ]] || fail 65 "invalid unit"
      validate_since "$since"
      validate_lines "$lines"
      journalctl --no-pager --output=short-iso --unit "$unit" --since "$since ago" -n "$lines"
      ;;

    readonly:service-status)
      need_cmd systemctl
      local unit=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --unit) unit="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$unit" =~ $ALLOWED_UNITS_REGEX ]] || fail 65 "invalid unit"
      systemctl show "$unit" --property=Id,LoadState,ActiveState,SubState,ExecMainPID,RestartUSec,MemoryCurrent,NRestarts --no-pager
      ;;

    *)
      fail 64 "linux.systemd cannot handle $mode:$cmd"
      ;;
  esac
}
