agentictl_require_staged_source() {
  local source_file="$1"
  local source_real staging_real
  need_cmd readlink
  source_real="$(readlink -f "$source_file")" || fail 66 "source file not readable"
  staging_real="$(readlink -f "$STAGING_DIR")" || fail 66 "staging directory not readable"
  [[ "$source_real" == "$staging_real"/* ]] || fail 77 "source must be under staging directory: $STAGING_DIR"
}

agentictl_install_staged_file() {
  local tmp="$1" target="$2"
  local owner="${SUDO_USER:-${USER:-}}"
  if [[ -n "$owner" ]] && id "$owner" >/dev/null 2>&1; then
    install -m 0640 -o "$owner" -g "$(id -gn "$owner")" "$tmp" "$target"
  else
    install -m 0640 "$tmp" "$target"
  fi
}

agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    act:config-stage)
      local name="" target tmp bytes extra
      EXECUTE="false"; DRY_RUN="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) name="${2:-}"; shift 2 ;;
          --dry-run) DRY_RUN="true"; shift ;;
          --execute) EXECUTE="true"; shift ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$name" =~ $SAFE_STAGE_NAME_REGEX ]] || fail 65 "invalid stage name"
      [[ "$name" != *".."* ]] || fail 65 "parent-directory references are not allowed"
      target="$STAGING_DIR/$name"
      if [[ "$DRY_RUN" == "true" ]]; then
        printf '{"ok":true,"dry_run":true,"action":"config-stage","path":"%s","max_bytes":%s}\n' "$target" "$AGENTICTL_MAX_CONFIG_BYTES"
        return 0
      fi
      require_execute_flag
      tmp="$STAGING_DIR/.$name.tmp.$$"
      dd bs=1 count="$AGENTICTL_MAX_CONFIG_BYTES" of="$tmp" status=none 2>/dev/null
      bytes="$(wc -c < "$tmp" | tr -d ' ')"
      if IFS= read -r -n 1 extra; then
        rm -f "$tmp"
        fail 65 "stdin exceeds AGENTICTL_MAX_CONFIG_BYTES"
      fi
      agentictl_install_staged_file "$tmp" "$target"
      rm -f "$tmp"
      audit_action "config-stage" "$target" "execute" "bytes=$bytes"
      printf '{"ok":true,"action":"config-stage","path":"%s","bytes":%s}\n' "$target" "$bytes"
      ;;

    act:config-apply)
      local target="" source_file="" backup
      EXECUTE="false"; DRY_RUN="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --target) target="${2:-}"; shift 2 ;;
          --source) source_file="${2:-}"; shift 2 ;;
          --dry-run) DRY_RUN="true"; shift ;;
          --execute) EXECUTE="true"; shift ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ -n "$target" && -n "$source_file" ]] || fail 65 "--target and --source are required"
      [[ -r "$source_file" ]] || fail 66 "source file not readable"
      contains_word "$target" "$ALLOW_CONFIG_TARGETS" || fail 77 "config target not allowed: $target"
      agentictl_require_staged_source "$source_file"
      if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -e "$target" ]]; then
          diff -u "$target" "$source_file" || true
        else
          printf '{"ok":true,"dry_run":true,"action":"config-apply","target":"%s","source":"%s","target_exists":false}\n' "$target" "$source_file"
        fi
        return 0
      fi
      require_execute_flag
      if [[ -e "$target" ]]; then
        backup="$BACKUP_DIR/$(basename "$target").$(date +%Y%m%dT%H%M%S).bak"
        cp -a "$target" "$backup"
      else
        backup=""
        install -d -m 0755 "$(dirname "$target")"
      fi
      install -m 0644 "$source_file" "$target"
      audit_action "config-apply" "$target" "execute" "backup=$backup"
      printf '{"ok":true,"action":"config-apply","target":"%s","backup":"%s"}\n' "$target" "$backup"
      ;;

    *)
      fail 64 "linux.config cannot handle $mode:$cmd"
      ;;
  esac
}
