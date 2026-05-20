#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

for key in /keys/agentictl_ro.pub /keys/agentictl_act.pub; do
  for _ in $(seq 1 30); do
    [[ -s "$key" ]] && break
    sleep 1
  done
  [[ -s "$key" ]] || {
    printf 'missing key: %s\n' "$key" >&2
    exit 1
  }
done

ssh-keygen -A

/src/install/install-node.sh \
  --user agentictl-smoke \
  --base-dir /opt/agentictl-smoke \
  --readonly-public-key-file /keys/agentictl_ro.pub \
  --allow-service-restart "" \
  --allow-package-install "" \
  --allow-config-targets "" \
  --allow-read-roots "/var/log /etc" \
  --allow-log-roots "/var/log" \
  --deny-read-paths "/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"

[[ ! -e /etc/sudoers.d/agentictl ]] || {
  printf 'readonly-only install unexpectedly created sudoers\n' >&2
  exit 1
}

/src/install/install-node.sh \
  --split-users \
  --readonly-public-key-file /keys/agentictl_ro.pub \
  --action-public-key-file /keys/agentictl_act.pub \
  --allow-service-restart "fake.service agentictl-agent.service" \
  --allow-package-install "htop jq" \
  --allow-config-targets "/etc/agentictl/runtime.yaml" \
  --allow-read-roots "/var/log /etc" \
  --allow-log-roots "/var/log" \
  --deny-read-paths "/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"

sudo -l -U agentictl-act | grep -F '/opt/agentictl/bin/agentictl-act' >/dev/null
if sudo -l -U agentictl-ro 2>/dev/null | grep -F '/opt/agentictl/bin/agentictl-act' >/dev/null; then
  printf 'readonly split user unexpectedly has agentictl-act sudo permission\n' >&2
  exit 1
fi
id -nG agentictl-ro | grep -w 'agentictl-audit' >/dev/null
id -nG agentictl-act | grep -w 'agentictl-audit' >/dev/null
[[ "$(stat -c '%U:%G:%a' /opt/agentictl/state/audit.log)" == 'root:agentictl-audit:660' ]] || {
  printf 'unexpected audit log permissions\n' >&2
  exit 1
}
[[ "$(stat -c '%U:%a' /opt/agentictl/state/incoming)" == 'agentictl-act:750' ]] || {
  printf 'unexpected staging directory permissions\n' >&2
  exit 1
}

printf 'agentictl test log line 1\nagentictl test log line 2\n' > /var/log/agentictl-test.log
printf 'node_setting=true\n' > /etc/agentictl-test.conf

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/agentictl-test.conf <<'CONFIG'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers agentictl-ro agentictl-act
LogLevel VERBOSE
CONFIG

exec /usr/sbin/sshd -D -e
