#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_TOOL_DIR="$ROOT/skills/agentictl-ssh/scripts"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/config" "$TMP_DIR/state/incoming" "$TMP_DIR/readroot/etc" "$TMP_DIR/readroot/var/log" "$TMP_DIR/fakebin"
printf 'setting=true\n' > "$TMP_DIR/readroot/etc/app.conf"
printf 'secret=true\n' > "$TMP_DIR/readroot/etc/secret.conf"
printf 'line one\nline two\n' > "$TMP_DIR/readroot/var/log/app.log"
cat > "$TMP_DIR/fakebin/apt-get" <<'FAKE_APT'
#!/usr/bin/env bash
printf 'fake apt-get %s\n' "$*"
FAKE_APT
chmod +x "$TMP_DIR/fakebin/apt-get"
for fake_manager in dnf yum zypper apk pacman; do
  cp "$TMP_DIR/fakebin/apt-get" "$TMP_DIR/fakebin/$fake_manager"
done
cat > "$TMP_DIR/fakebin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
last=""
for arg in "$@"; do
  last="$arg"
done
case "$last" in
  health) printf '{"ok":true,"host":"fake-node"}\n' ;;
  *) printf '{"ok":true,"cmd":"%s"}\n' "$last" ;;
esac
FAKE_SSH
chmod +x "$TMP_DIR/fakebin/ssh"
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
export PATH="$TMP_DIR/fakebin:$PATH"

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
check_contains "$output" '"manager":"apt"'

for package_manager in apt dnf yum zypper apk pacman; do
  output="$(AGENTICTL_PACKAGE_MANAGER="$package_manager" "$ROOT/bin/agentictl" act package-install --name htop --dry-run)"
  check_contains "$output" "\"manager\":\"$package_manager\""
done

check_fails env SSH_ORIGINAL_COMMAND='package-install --name curl --dry-run' "$ROOT/bin/agentictl" act
check_fails env SSH_ORIGINAL_COMMAND='service-restart --unit ollama.service;uname -a --dry-run' "$ROOT/bin/agentictl" act
check_fails env SSH_ORIGINAL_COMMAND='service-restart --unit ../ollama.service --dry-run' "$ROOT/bin/agentictl" act

output="$(printf 'runtime: test\n' | "$ROOT/bin/agentictl" act config-stage --name runtime.yaml --execute)"
check_contains "$output" '"action":"config-stage"'

output="$("$ROOT/bin/agentictl" act config-apply --target /etc/agentictl/runtime.yaml --source "$TMP_DIR/state/incoming/runtime.yaml" --dry-run)"
check_contains "$output" '"target_exists":false'

output="$("$ROOT/bin/agentictl" act capabilities)"
check_contains "$output" '"mode":"act"'

output="$("$ROOT/bin/agentictl" readonly capabilities)"
check_contains "$output" 'package-list'

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
output="$("$ROOT/bin/agentictl-nodes" add --alias node-ro --host node.example.net --mode readonly --identity "$TMP_DIR/key" --role "GPU inference node for local models")"
check_contains "$output" '"action":"add"'
check_contains "$output" '"user":"agentictl-ro"'

output="$("$ROOT/bin/agentictl-nodes" add --alias node-act --host node.example.net --mode act --identity "$TMP_DIR/key-act")"
check_contains "$output" '"user":"agentictl-act"'

output="$("$ROOT/bin/agentictl-nodes" add --alias node-legacy --host node.example.net --user agentictl --mode act --identity "$TMP_DIR/key-legacy")"
check_contains "$output" '"user":"agentictl"'

output="$("$ROOT/bin/agentictl-nodes" list)"
check_contains "$output" '"alias":"node-ro"'
check_contains "$output" '"user":"agentictl-ro"'
check_contains "$output" '"alias":"node-act"'
check_contains "$output" '"user":"agentictl-act"'
check_contains "$output" 'GPU inference node'

output="$(bash "$SKILL_TOOL_DIR/agentictl-node-tool.sh" list)"
check_contains "$output" '"alias":"node-ro"'

diff -u "$ROOT/bin/agentictl-nodes" "$ROOT/skills/agentictl-ssh/resources/bin/agentictl-nodes" >/dev/null
pass_count=$((pass_count + 1))

output="$(bash "$ROOT/skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh" --bin-dir "$TMP_DIR/installed-bin")"
check_contains "$output" '"ok":true'
check_contains "$output" 'agentictl-bootstrap-instructions.sh'

output="$("$TMP_DIR/installed-bin/agentictl-node-tool.sh" list)"
check_contains "$output" '"alias":"node-ro"'

output="$(bash "$SKILL_TOOL_DIR/agentictl-bootstrap-instructions.sh" --host node.example.net --admin-user admin --role "GPU inference node")"
check_contains "$output" 'ssh "$ADMIN_USER@$NODE_HOST"'
check_contains "$output" 'agentictl-node-tool.sh add'

output="$(bash "$SKILL_TOOL_DIR/agentictl-bootstrap-instructions.sh" --host node.example.net --admin-user admin --readonly-extra-groups "adm systemd-journal")"
check_contains "$output" '--readonly-extra-groups'

output="$("$TMP_DIR/installed-bin/agentictl-bootstrap-instructions.sh" --host node.example.net --admin-user admin --readonly-only)"
check_contains "$output" '--readonly-public-key-file'

output="$(printf 'GPU inference node with NVIDIA runtime and Ollama service\n' | "$ROOT/bin/agentictl-nodes" role-set --node node-ro --source test)"
check_contains "$output" '"action":"role-set"'

output="$("$ROOT/bin/agentictl-nodes" role-show --node node-ro)"
check_contains "$output" 'NVIDIA runtime'

output="$(printf '{"ok":true}\n' | "$ROOT/bin/agentictl-nodes" record --node node-ro --kind health --source 'ssh node-ro health')"
check_contains "$output" '"path":'

output="$(bash "$SKILL_TOOL_DIR/agentictl-ssh-tool.sh" --target node-ro --record-kind health-tool -- health)"
check_contains "$output" '"host":"fake-node"'

check_fails bash "$SKILL_TOOL_DIR/agentictl-ssh-tool.sh" --target node-ro -- package-install --name htop --execute

output="$("$ROOT/bin/agentictl-nodes" history --node node-ro --kind health --limit 5)"
check_contains "$output" '"readings":['

output="$("$ROOT/bin/agentictl-nodes" history --node node-ro --kind health-tool --limit 5)"
check_contains "$output" 'health-tool'

printf 'ok %s tests\n' "$pass_count"
