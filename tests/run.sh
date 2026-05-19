#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/state/incoming" "$TMP_DIR/readroot/etc" "$TMP_DIR/readroot/var/log"
printf 'setting=true\n' > "$TMP_DIR/readroot/etc/app.conf"
printf 'secret=true\n' > "$TMP_DIR/readroot/etc/secret.conf"
printf 'line one\nline two\n' > "$TMP_DIR/readroot/var/log/app.log"
cat > "$TMP_DIR/config/policy.env" <<'POLICY'
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="htop jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml"
AGENTICTL_MAX_CONFIG_BYTES=1048576
POLICY
{
  printf 'ALLOW_READ_ROOTS=%q\n' "$TMP_DIR/readroot/etc $TMP_DIR/readroot/var/log"
  printf 'ALLOW_LOG_ROOTS=%q\n' "$TMP_DIR/readroot/var/log"
  printf 'DENY_READ_PATHS=%q\n' "$TMP_DIR/readroot/etc/secret.conf"
  printf 'AGENTICTL_MAX_READ_BYTES=4096\n'
  printf 'AGENTICTL_MAX_LIST_ENTRIES=100\n'
  printf 'AGENTICTL_MAX_LIST_DEPTH=3\n'
} >> "$TMP_DIR/config/policy.env"

export AGENTICTL_BASE_DIR="$TMP_DIR"
export AGENTICTL_ACT_SUDO=never

pass_count=0

check_contains() {
  local output="$1" needle="$2"
  [[ "$output" == *"$needle"* ]] || {
    printf 'expected output to contain %s, got:\n%s\n' "$needle" "$output" >&2
    exit 1
  }
  pass_count=$((pass_count + 1))
}

check_fails() {
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'expected failure, got success:\n%s\n' "$output" >&2
    exit 1
  }
  pass_count=$((pass_count + 1))
}

output="$("$ROOT/bin/agentictl" act service-restart --unit ollama.service --dry-run)"
check_contains "$output" '"dry_run":true'

output="$(SSH_ORIGINAL_COMMAND='package-install --name htop --dry-run' "$ROOT/bin/agentictl" act)"
check_contains "$output" '"package":"htop"'

check_fails env SSH_ORIGINAL_COMMAND='package-install --name curl --dry-run' "$ROOT/bin/agentictl" act
check_fails env SSH_ORIGINAL_COMMAND='service-restart --unit ollama.service;uname -a --dry-run' "$ROOT/bin/agentictl" act
check_fails env SSH_ORIGINAL_COMMAND='service-restart --unit ../ollama.service --dry-run' "$ROOT/bin/agentictl" act

output="$(printf 'runtime: test\n' | "$ROOT/bin/agentictl" act config-stage --name runtime.yaml --execute)"
check_contains "$output" '"action":"config-stage"'

output="$("$ROOT/bin/agentictl" act config-apply --target /etc/agentictl/runtime.yaml --source "$TMP_DIR/state/incoming/runtime.yaml" --dry-run)"
check_contains "$output" '"target_exists":false'

output="$("$ROOT/bin/agentictl" act capabilities)"
check_contains "$output" '"mode":"act"'

output="$("$ROOT/bin/agentictl" readonly fs-list --path "$TMP_DIR/readroot/etc" --max-depth 1 --limit 20)"
check_contains "$output" '"entries":['

output="$("$ROOT/bin/agentictl" readonly fs-stat --path "$TMP_DIR/readroot/etc/app.conf")"
check_contains "$output" '"type":"file"'

output="$("$ROOT/bin/agentictl" readonly fs-read --path "$TMP_DIR/readroot/etc/app.conf" --max-bytes 100)"
check_contains "$output" 'setting=true'

output="$("$ROOT/bin/agentictl" readonly log-read --path "$TMP_DIR/readroot/var/log/app.log" --tail 1)"
check_contains "$output" 'line two'

check_fails "$ROOT/bin/agentictl" readonly fs-read --path "$TMP_DIR/readroot/etc/secret.conf"

export AGENTICTL_WORKSPACE_DIR="$TMP_DIR/workspace"
output="$("$ROOT/bin/agentictl-nodes" add --alias node-ro --host node.example.net --mode readonly --identity "$TMP_DIR/key")"
check_contains "$output" '"action":"add"'

output="$("$ROOT/bin/agentictl-nodes" list)"
check_contains "$output" '"alias":"node-ro"'

output="$(printf '{"ok":true}\n' | "$ROOT/bin/agentictl-nodes" record --node node-ro --kind health --source 'ssh node-ro health')"
check_contains "$output" '"path":'

output="$("$ROOT/bin/agentictl-nodes" history --node node-ro --kind health --limit 5)"
check_contains "$output" '"readings":['

printf 'ok %s tests\n' "$pass_count"
