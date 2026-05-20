# agentictl Operations

## Model

The managed node exposes dedicated SSH users. In the recommended split-user layout these are `agentictl-ro` and `agentictl-act`. The users have `/bin/sh` as their login shell because OpenSSH uses the user's shell to run forced commands. Access is confined with `authorized_keys` forced commands:

- `agentictl readonly` for diagnostics.
- `agentictl act` for allowlisted changes.

`agentictl` reads `SSH_ORIGINAL_COMMAND`, accepts only simple command tokens, rejects shell metacharacters, and dispatches to the mode-specific executor. It never invokes a general shell.

## Node Install

For OpenClaw-specific workspace setup, SSH aliases, verification prompts, and HEARTBEAT examples, see `docs/OPENCLAW.md`.

Generate at least one key pair on the agent host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_ro -C agentictl-ro
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_act -C agentictl-act
```

Install on each Linux node:

```bash
sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file ~/.ssh/agentictl_ro.pub \
  --action-public-key-file ~/.ssh/agentictl_act.pub \
  --allow-service-restart "ollama.service agentictl-agent.service" \
  --allow-package-install "htop jq" \
  --allow-config-targets "/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
```

Add SSH aliases on the agent host:

```sshconfig
Host node-ro
  HostName node.example.net
  User agentictl-ro
  IdentityFile ~/.ssh/agentictl_ro
  BatchMode yes

Host node-act
  HostName node.example.net
  User agentictl-act
  IdentityFile ~/.ssh/agentictl_act
  BatchMode yes
```

## Package

Build a simple tarball:

```bash
make package
```

Copy `dist/agentictl-<version>.tar.gz` to a node, extract it, and run `install/install-node.sh` from the extracted directory.

## Docker Test Harness

Run the end-to-end SSH test harness:

```bash
make test
```

The harness uses Docker Compose with an internal-only network. It starts:

- `keygen`: creates ephemeral read-only and action SSH keys in a Docker volume.
- `node`: installs the executor, configures `sshd`, and exposes only forced-command SSH inside Compose.
- `runner`: connects to `node` over Docker DNS and validates diagnostics, policy denials, dry-runs, staged config apply, and a fake `systemctl restart`.

## Policy

The installed policy lives at `/opt/agentictl/config/policy.env`.

Keep allowlists narrow:

```bash
ALLOW_SERVICE_RESTART="ollama.service"
ALLOW_PACKAGE_INSTALL="jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml"
AGENTICTL_MAX_CONFIG_BYTES=1048576
ALLOW_READ_ROOTS="/var/log /etc"
ALLOW_LOG_ROOTS="/var/log"
DENY_READ_PATHS="/etc/shadow /etc/gshadow /etc/ssh /etc/ssl/private /etc/sudoers /etc/sudoers.d"
AGENTICTL_MAX_READ_BYTES=262144
AGENTICTL_MAX_LIST_ENTRIES=2000
AGENTICTL_MAX_LIST_DEPTH=5
```

The action executor must be the only path to privileged changes. The installer adds a sudoers rule for `/opt/agentictl/bin/agentictl-act *` only when an action public key is installed. With `--split-users`, only `agentictl-act` receives that sudoers rule; `agentictl-ro` receives no sudo permission. If no action key is supplied, the managed sudoers file is removed.

## Audit

Audit records are appended to `/opt/agentictl/state/audit.log`. In split-user installs this file is owned by `root:agentictl-audit` with mode `0660`; both runtime users are members of that shared audit group, while `/opt/agentictl/state/incoming` and `/opt/agentictl/state/backups` remain owned by the action user. Review the audit log during incident response or when tuning allowlists.

## Skill Install

OpenClaw loads workspace skills from `<workspace>/skills`. Copy or keep this repository's `skills/agentictl-ssh` directory in the workspace, then start a new session or run:

```bash
openclaw skills list
```

The skill follows the OpenClaw `SKILL.md` layout and teaches the agent to use the safe SSH commands rather than arbitrary SSH.
