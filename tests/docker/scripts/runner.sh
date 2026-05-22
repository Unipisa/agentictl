#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SSH_COMMON=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/tmp/known_hosts
  -o ConnectTimeout=5
)

ssh_ro() {
  ssh "${SSH_COMMON[@]}" -i /keys/agentictl_ro agentictl-ro@node "$@"
}

ssh_act() {
  ssh "${SSH_COMMON[@]}" -i /keys/agentictl_act agentictl-act@node "$@"
}

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
  local output status
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

for _ in $(seq 1 30); do
  if ssh_ro capabilities >/tmp/agentictl-capabilities.json 2>/tmp/agentictl-ssh.err; then
    break
  fi
  sleep 1
done
[[ -s /tmp/agentictl-capabilities.json ]] || {
  cat /tmp/agentictl-ssh.err >&2 || true
  exit 1
}

output="$(cat /tmp/agentictl-capabilities.json)"
check_contains "$output" '"mode":"readonly"'

output="$(ssh_ro health)"
check_contains "$output" '"ok":true'

output="$(ssh_ro service-status --unit fake.service)"
check_contains "$output" 'ActiveState=active'

output="$(ssh_ro package-list --limit 20)"
check_contains "$output" '"manager":"dpkg"'

output="$(ssh_ro kernel-modules --limit 20)"
check_contains "$output" '"modules":['

output="$(ssh_ro fs-list --path /etc --max-depth 1 --limit 20)"
check_contains "$output" '"entries":['

output="$(ssh_ro fs-stat --path /etc/agentictl-test.conf)"
check_contains "$output" '"type":"file"'

output="$(ssh_ro fs-read --path /etc/agentictl-test.conf --max-bytes 100)"
check_contains "$output" 'node_setting=true'

output="$(ssh_ro log-read --path /var/log/agentictl-test.log --tail 1)"
check_contains "$output" 'agentictl test log line 2'

output="$(ssh_ro log-read --path /var/log/agentictl-private/private.log --tail 1)"
check_contains "$output" 'private log line 2'

check_fails ssh_ro fs-read --path /etc/ssh/sshd_config

output="$(ssh_act capabilities)"
check_contains "$output" '"mode":"act"'

output="$(ssh_act service-restart --unit fake.service --dry-run)"
check_contains "$output" '"dry_run":true'

check_fails ssh_act service-restart --unit blocked.service --dry-run
check_fails ssh_act 'service-restart --unit fake.service;uname -a --dry-run'
check_fails ssh_act service-restart --unit ../fake.service --dry-run
check_fails ssh_ro package-install --name jq --dry-run

output="$(ssh_act package-install --name jq --dry-run)"
check_contains "$output" '"package":"jq"'
check_contains "$output" '"manager":"apt"'

output="$(printf 'runtime: docker\n' | ssh_act config-stage --name runtime.yaml --execute)"
check_contains "$output" '"action":"config-stage"'

output="$(ssh_act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --dry-run)"
check_contains "$output" '"target_exists":false'

output="$(ssh_act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --execute)"
check_contains "$output" '"action":"config-apply"'

output="$(ssh_act service-restart --unit fake.service --execute)"
check_contains "$output" '"result":"active"'

printf 'ok %s docker ssh tests\n' "$pass_count"
