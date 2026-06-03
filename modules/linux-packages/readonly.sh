agentictl_print_upgrade_entry() {
  local comma="$1" name="$2" current="$3" available="$4" raw="${5:-}"
  printf '%s{"name":%s,"current_version":%s,"available_version":%s,"raw":%s}' \
    "$comma" \
    "$(json_string "$name")" \
    "$(json_string "$current")" \
    "$(json_string "$available")" \
    "$(json_string "$raw")"
}

agentictl_module_dispatch() {
  local mode="$1" cmd="$2"; shift 2
  case "$mode:$cmd" in
    readonly:package-list)
      local limit="1000" manager="" count comma line name version status
      local -a list_cmd=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --limit) limit="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      validate_positive_int "$limit" "--limit" "$MAX_PACKAGE_LIMIT"
      if command -v dpkg-query >/dev/null 2>&1; then
        manager="dpkg"
        list_cmd=(dpkg-query -W -f='${Package}\t${Version}\t${db:Status-Abbrev}\n')
      elif command -v rpm >/dev/null 2>&1; then
        manager="rpm"
        list_cmd=(rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\tinstalled\n')
      elif command -v apk >/dev/null 2>&1; then
        manager="apk"
        list_cmd=(apk info -v)
      elif command -v pacman >/dev/null 2>&1; then
        manager="pacman"
        list_cmd=(pacman -Q)
      else
        fail 70 "no supported package database found"
      fi
      printf '{"ok":true,"manager":%s,"limit":%s,"packages":[' "$(json_string "$manager")" "$limit"
      count=0
      comma=""
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$manager" == "apk" ]]; then
          name="${line%-[0-9]*}"
          version="${line#"$name"-}"
          status="installed"
        elif [[ "$manager" == "pacman" ]]; then
          IFS=' ' read -r name version <<< "$line"
          status="installed"
        else
          IFS=$'\t' read -r name version status <<< "$line"
        fi
        [[ -n "${name:-}" ]] || continue
        printf '%s{"name":%s,"version":%s,"status":%s}' \
          "$comma" \
          "$(json_string "$name")" \
          "$(json_string "${version:-}")" \
          "$(json_string "${status:-}")"
        comma=","
        count=$((count + 1))
        (( count >= limit )) && break
      done < <("${list_cmd[@]}" 2>/dev/null | sort)
      printf '],"truncated":%s}\n' "$([[ "$count" -ge "$limit" ]] && printf true || printf false)"
      ;;

    readonly:package-upgrades)
      local limit="1000" manager="" count comma line name current available
      local upgrade_output upgrade_status name_arch _repo _status _arch _op _rest
      local -a list_cmd=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --limit) limit="${2:-}"; shift 2 ;;
          *) fail 64 "unknown argument: $1" ;;
        esac
      done
      validate_positive_int "$limit" "--limit" "$MAX_PACKAGE_LIMIT"
      if command -v apt-get >/dev/null 2>&1; then
        manager="apt"
        list_cmd=(apt-get -s upgrade)
      elif command -v dnf >/dev/null 2>&1; then
        manager="dnf"
        list_cmd=(dnf check-update -q)
      elif command -v yum >/dev/null 2>&1; then
        manager="yum"
        list_cmd=(yum check-update -q)
      elif command -v zypper >/dev/null 2>&1; then
        manager="zypper"
        list_cmd=(zypper --non-interactive list-updates)
      elif command -v apk >/dev/null 2>&1; then
        manager="apk"
        list_cmd=(apk version -l '<')
      elif command -v pacman >/dev/null 2>&1; then
        manager="pacman"
        list_cmd=(pacman -Qu)
      else
        fail 70 "no supported package upgrade source found"
      fi

      printf '{"ok":true,"manager":%s,"limit":%s,"upgrades":[' "$(json_string "$manager")" "$limit"
      count=0
      comma=""
      set +e
      upgrade_output="$("${list_cmd[@]}" 2>/dev/null)"
      upgrade_status=$?
      set -e
      case "$manager:$upgrade_status" in
        dnf:100|yum:100) ;;
        *:0) ;;
        *) upgrade_output="" ;;
      esac
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        name=""; current=""; available=""
        case "$manager" in
          apt)
            if [[ "$line" =~ ^Inst[[:space:]]+([^[:space:]]+)[[:space:]]+\[([^]]*)\][[:space:]]+\(([^[:space:]]+) ]]; then
              name="${BASH_REMATCH[1]}"
              current="${BASH_REMATCH[2]}"
              available="${BASH_REMATCH[3]}"
            else
              continue
            fi
            ;;
          dnf|yum)
            [[ "$line" == *" "* ]] || continue
            read -r name_arch available _repo <<< "$line"
            [[ "$name_arch" != Loaded* && "$name_arch" != Obsoleting* ]] || continue
            name="${name_arch%.*}"
            ;;
          zypper)
            [[ "$line" == *"|"* ]] || continue
            IFS='|' read -r _status _repo name current available _arch <<< "$line"
            name="$(trim_spaces "${name:-}")"
            current="$(trim_spaces "${current:-}")"
            available="$(trim_spaces "${available:-}")"
            [[ -n "$name" && "$name" != Name ]] || continue
            ;;
          apk)
            read -r name _op available _rest <<< "$line"
            [[ -n "$name" ]] || continue
            ;;
          pacman)
            local pacman_upgrade_re='^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+->[[:space:]]+([^[:space:]]+)'
            if [[ "$line" =~ $pacman_upgrade_re ]]; then
              name="${BASH_REMATCH[1]}"
              current="${BASH_REMATCH[2]}"
              available="${BASH_REMATCH[3]}"
            else
              continue
            fi
            ;;
        esac
        [[ -n "$name" ]] || continue
        agentictl_print_upgrade_entry "$comma" "$name" "$current" "$available" "$line"
        comma=","
        count=$((count + 1))
        (( count >= limit )) && break
      done <<< "$upgrade_output"
      printf '],"truncated":%s}\n' "$([[ "$count" -ge "$limit" ]] && printf true || printf false)"
      ;;

    *)
      fail 64 "linux.packages cannot handle $mode:$cmd"
      ;;
  esac
}
