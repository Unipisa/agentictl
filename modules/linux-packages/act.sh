agentictl_detect_package_installer() {
  local pkg="$1" requested="${AGENTICTL_PACKAGE_MANAGER:-${OPENCLAW_PACKAGE_MANAGER:-auto}}"
  PACKAGE_MANAGER=""
  PACKAGE_INSTALLER=()

  case "$requested" in
    auto) ;;
    apt|apt-get)
      need_cmd apt-get
      PACKAGE_MANAGER="apt"
      PACKAGE_INSTALLER=(apt-get install -y --no-install-recommends "$pkg")
      return 0
      ;;
    dnf)
      need_cmd dnf
      PACKAGE_MANAGER="dnf"
      PACKAGE_INSTALLER=(dnf install -y "$pkg")
      return 0
      ;;
    yum)
      need_cmd yum
      PACKAGE_MANAGER="yum"
      PACKAGE_INSTALLER=(yum install -y "$pkg")
      return 0
      ;;
    zypper)
      need_cmd zypper
      PACKAGE_MANAGER="zypper"
      PACKAGE_INSTALLER=(zypper --non-interactive install "$pkg")
      return 0
      ;;
    apk)
      need_cmd apk
      PACKAGE_MANAGER="apk"
      PACKAGE_INSTALLER=(apk add --no-cache "$pkg")
      return 0
      ;;
    pacman)
      need_cmd pacman
      PACKAGE_MANAGER="pacman"
      PACKAGE_INSTALLER=(pacman -S --noconfirm "$pkg")
      return 0
      ;;
    *)
      fail 65 "unsupported AGENTICTL_PACKAGE_MANAGER: $requested"
      ;;
  esac

  if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
    PACKAGE_INSTALLER=(apt-get install -y --no-install-recommends "$pkg")
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
    PACKAGE_INSTALLER=(dnf install -y "$pkg")
  elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
    PACKAGE_INSTALLER=(yum install -y "$pkg")
  elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_MANAGER="zypper"
    PACKAGE_INSTALLER=(zypper --non-interactive install "$pkg")
  elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
    PACKAGE_INSTALLER=(apk add --no-cache "$pkg")
  elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
    PACKAGE_INSTALLER=(pacman -S --noconfirm "$pkg")
  else
    fail 70 "no supported package manager found"
  fi
}

agentictl_detect_package_upgrader() {
  local target="$1" pkg="${2:-}" requested="${AGENTICTL_PACKAGE_MANAGER:-${OPENCLAW_PACKAGE_MANAGER:-auto}}"
  PACKAGE_MANAGER=""
  PACKAGE_UPGRADER=()

  agentictl_choose_package_upgrader() {
    local manager="$1"
    case "$manager" in
      apt|apt-get)
        need_cmd apt-get
        PACKAGE_MANAGER="apt"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(apt-get upgrade -y)
        else
          PACKAGE_UPGRADER=(apt-get install -y --only-upgrade --no-install-recommends "$pkg")
        fi
        ;;
      dnf)
        need_cmd dnf
        PACKAGE_MANAGER="dnf"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(dnf upgrade -y)
        else
          PACKAGE_UPGRADER=(dnf upgrade -y "$pkg")
        fi
        ;;
      yum)
        need_cmd yum
        PACKAGE_MANAGER="yum"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(yum update -y)
        else
          PACKAGE_UPGRADER=(yum update -y "$pkg")
        fi
        ;;
      zypper)
        need_cmd zypper
        PACKAGE_MANAGER="zypper"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(zypper --non-interactive update)
        else
          PACKAGE_UPGRADER=(zypper --non-interactive update "$pkg")
        fi
        ;;
      apk)
        need_cmd apk
        PACKAGE_MANAGER="apk"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(apk upgrade)
        else
          PACKAGE_UPGRADER=(apk upgrade "$pkg")
        fi
        ;;
      pacman)
        need_cmd pacman
        PACKAGE_MANAGER="pacman"
        if [[ "$target" == "all" ]]; then
          PACKAGE_UPGRADER=(pacman -Syu --noconfirm)
        else
          PACKAGE_UPGRADER=(pacman -S --noconfirm "$pkg")
        fi
        ;;
      *)
        fail 65 "unsupported AGENTICTL_PACKAGE_MANAGER: $manager"
        ;;
    esac
  }

  case "$requested" in
    auto) ;;
    apt|apt-get|dnf|yum|zypper|apk|pacman)
      agentictl_choose_package_upgrader "$requested"
      return 0
      ;;
    *)
      fail 65 "unsupported AGENTICTL_PACKAGE_MANAGER: $requested"
      ;;
  esac

  if command -v apt-get >/dev/null 2>&1; then
    agentictl_choose_package_upgrader apt
  elif command -v dnf >/dev/null 2>&1; then
    agentictl_choose_package_upgrader dnf
  elif command -v yum >/dev/null 2>&1; then
    agentictl_choose_package_upgrader yum
  elif command -v zypper >/dev/null 2>&1; then
    agentictl_choose_package_upgrader zypper
  elif command -v apk >/dev/null 2>&1; then
    agentictl_choose_package_upgrader apk
  elif command -v pacman >/dev/null 2>&1; then
    agentictl_choose_package_upgrader pacman
  else
    fail 70 "no supported package manager found"
  fi
}

agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    act:package-install)
      local pkg=""
      EXECUTE="false"; DRY_RUN="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) pkg="${2:-}"; shift 2 ;;
          --dry-run) DRY_RUN="true"; shift ;;
          --execute) EXECUTE="true"; shift ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$pkg" =~ $ALLOWED_PACKAGES_REGEX ]] || fail 65 "invalid package name"
      contains_word "$pkg" "$ALLOW_PACKAGE_INSTALL" || fail 77 "package not allowed: $pkg"
      agentictl_detect_package_installer "$pkg"
      if [[ "$DRY_RUN" == "true" ]]; then
        printf '{"ok":true,"dry_run":true,"action":"package-install","package":"%s","manager":%s}\n' \
          "$pkg" \
          "$(json_string "$PACKAGE_MANAGER")"
        return 0
      fi
      require_execute_flag
      "${PACKAGE_INSTALLER[@]}"
      audit_action "package-install" "$pkg" "execute" "manager=$PACKAGE_MANAGER"
      printf '{"ok":true,"action":"package-install","package":"%s","manager":%s}\n' \
        "$pkg" \
        "$(json_string "$PACKAGE_MANAGER")"
      ;;

    act:package-upgrade)
      local pkg="" target=""
      EXECUTE="false"; DRY_RUN="false"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) pkg="${2:-}"; target="package"; shift 2 ;;
          --all) target="all"; shift ;;
          --dry-run) DRY_RUN="true"; shift ;;
          --execute) EXECUTE="true"; shift ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      [[ "$target" == "package" || "$target" == "all" ]] || fail 65 "use --name PACKAGE or --all"
      if [[ "$target" == "package" ]]; then
        [[ "$pkg" =~ $ALLOWED_PACKAGES_REGEX ]] || fail 65 "invalid package name"
        contains_word "$pkg" "$ALLOW_PACKAGE_UPGRADE" || fail 77 "package upgrade not allowed: $pkg"
      else
        [[ "$ALLOW_PACKAGE_UPGRADE_ALL" == "true" ]] || fail 77 "package upgrade all is not allowed"
      fi
      agentictl_detect_package_upgrader "$target" "$pkg"
      if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$target" == "all" ]]; then
          printf '{"ok":true,"dry_run":true,"action":"package-upgrade","target":"all","manager":%s}\n' \
            "$(json_string "$PACKAGE_MANAGER")"
        else
          printf '{"ok":true,"dry_run":true,"action":"package-upgrade","package":"%s","manager":%s}\n' \
            "$pkg" \
            "$(json_string "$PACKAGE_MANAGER")"
        fi
        return 0
      fi
      require_execute_flag
      "${PACKAGE_UPGRADER[@]}"
      if [[ "$target" == "all" ]]; then
        audit_action "package-upgrade" "all" "execute" "manager=$PACKAGE_MANAGER"
        printf '{"ok":true,"action":"package-upgrade","target":"all","manager":%s}\n' \
          "$(json_string "$PACKAGE_MANAGER")"
      else
        audit_action "package-upgrade" "$pkg" "execute" "manager=$PACKAGE_MANAGER"
        printf '{"ok":true,"action":"package-upgrade","package":"%s","manager":%s}\n' \
          "$pkg" \
          "$(json_string "$PACKAGE_MANAGER")"
      fi
      ;;

    *)
      fail 64 "linux.packages cannot handle $mode:$cmd"
      ;;
  esac
}
