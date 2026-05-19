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
  --readonly-public-key-file /keys/agentictl_ro.pub \
  --action-public-key-file /keys/agentictl_act.pub \
  --allow-service-restart "fake.service agentictl-agent.service" \
  --allow-package-install "htop jq" \
  --allow-config-targets "/etc/agentictl/runtime.yaml" \
  --allow-read-roots "/var/log /etc" \
  --allow-log-roots "/var/log" \
  --deny-read-paths "/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"

printf 'agentictl test log line 1\nagentictl test log line 2\n' > /var/log/agentictl-test.log
printf 'node_setting=true\n' > /etc/agentictl-test.conf

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/agentictl-test.conf <<'CONFIG'
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers agentictl
LogLevel VERBOSE
CONFIG

exec /usr/sbin/sshd -D -e
