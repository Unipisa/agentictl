#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

mkdir -p /keys

if [[ ! -f /keys/agentictl_ro ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /keys/agentictl_ro -C agentictl-test-readonly
fi

if [[ ! -f /keys/agentictl_act ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /keys/agentictl_act -C agentictl-test-action
fi

chmod 600 /keys/agentictl_ro /keys/agentictl_act
chmod 644 /keys/agentictl_ro.pub /keys/agentictl_act.pub
