agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    act:service-restart)
      local unit="" result
      EXECUTE="false"; DRY_RUN="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --unit) unit="${2:-}"; shift 2 ;;
          --dry-run) DRY_RUN="true"; shift ;;
          --execute) EXECUTE="true"; shift ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$unit" =~ $ALLOWED_UNITS_REGEX ]] || fail 65 "invalid unit"
      contains_word "$unit" "$ALLOW_SERVICE_RESTART" || fail 77 "unit not allowed: $unit"
      if [[ "$DRY_RUN" == "true" ]]; then
        printf '{"ok":true,"dry_run":true,"action":"service-restart","unit":"%s"}\n' "$unit"
        return 0
      fi
      require_execute_flag
      need_cmd systemctl
      systemctl restart "$unit"
      systemctl is-active --quiet "$unit" && result="active" || result="not-active"
      audit_action "service-restart" "$unit" "execute" "$result"
      printf '{"ok":true,"action":"service-restart","unit":"%s","result":"%s"}\n' "$unit" "$result"
      ;;

    *)
      fail 64 "linux.systemd cannot handle $mode:$cmd"
      ;;
  esac
}
