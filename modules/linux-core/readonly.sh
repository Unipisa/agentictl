agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    readonly:health)
      local host uptime_text disk_text
      host="$(hostname 2>/dev/null || true)"
      uptime_text="$(uptime 2>/dev/null || true)"
      disk_text="$(df -h / 2>/dev/null | tail -1 || true)"
      printf '{"ok":true,"host":%s,"uptime":%s,"disk":%s}\n' \
        "$(json_string "$host")" \
        "$(json_string "$uptime_text")" \
        "$(json_string "$disk_text")"
      ;;
    *)
      fail 64 "linux.core cannot handle $mode:$cmd"
      ;;
  esac
}
