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
  --allow-package-upgrade "htop jq" \
  --allow-package-upgrade-all false \
  --allow-config-targets "/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
```

If `agentictl-ro` must read logs that are group-protected, add existing log-reader groups explicitly:

```bash
# Add this option to the install command when these groups exist on the node:
--readonly-extra-groups "adm systemd-journal"
```

This does not grant sudo. It only lets the read-only forced-command user satisfy Unix file permissions for logs such as `/var/log/nginx/*.log` when those files are readable by one of the selected groups. If your distro uses a different group or ACL policy, use that group instead.

Add SSH aliases in `~/.ssh/config` on the agent host, meaning the host, user account, or container that will run `ssh`.
These aliases are client-side shortcuts, not settings on the managed node:

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

Verify the aliases from the same environment before giving them to an agent:

```bash
ssh node-ro health
ssh node-act capabilities
```

For OpenClaw-specific alias setup, including copy/paste commands and container notes, see `docs/OPENCLAW.md`.

## Package

Build a simple tarball:

```bash
make package
```

Copy `dist/agentictl-<version>.tar.gz` to a node, extract it, and run `install/install-node.sh` from the extracted directory.

When operating from OpenClaw, the usual source of the node-side version is the tarball bundled inside the updated skill under `skills/agentictl-ssh/resources/dist/`. `agentictl-fleet-sync.sh --source skill` uses that artifact and its manifest. Use `--source repo --repo-dir PATH --git-pull` to pull and rebuild from a local Git checkout, or `--source tarball --tarball PATH --manifest PATH` for an explicit artifact.

Fleet upgrade example:

```bash
agentictl-fleet-sync.sh \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Fleet uninstall example:

```bash
agentictl-fleet-sync.sh \
  --mode uninstall \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Default uninstall removes managed SSH access, sudoers, and installed binaries. It preserves state/config unless `--remove-base-dir` is supplied, and it preserves runtime users unless `--remove-users` is supplied.

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
ALLOW_PACKAGE_UPGRADE="jq"
ALLOW_PACKAGE_UPGRADE_ALL=false
AGENTICTL_PACKAGE_MANAGER=auto
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

`ALLOW_LOG_ROOTS` controls where `log-read` may read. It does not override Unix file permissions. If a log file is readable only by `root` or a group, grant read-only access through `--readonly-extra-groups` or filesystem ACLs, not by giving sudo to the read-only user.

## Software Inventory

Use read-only inventory before proposing package changes:

```bash
ssh node-ro package-list --limit 5000
ssh node-ro package-upgrades --limit 500
ssh node-ro kernel-modules --limit 2000
```

Save the intended node role locally with `bin/agentictl-nodes role-set`, then record package and module snapshots with `bin/agentictl-nodes record`. Package changes still go through `ssh node-act package-install --name PACKAGE --dry-run` or `ssh node-act package-upgrade --name PACKAGE --dry-run`. When OpenClaw executes changes, use `agentictl-approval-tool.sh` to approve one normalized operation across all intended action aliases, then execute the approved plan. Full upgrades require `ALLOW_PACKAGE_UPGRADE_ALL=true` and should be reviewed separately from single-package changes.

`package-list` reads installed packages from `dpkg-query`, `rpm`, `apk`, or `pacman` when available. `package-install` supports `apt-get`, `dnf`, `yum`, `zypper`, `apk`, and `pacman`; dry-run and execute output include the selected manager. Auto-detection is normally enough, but a node policy can set `AGENTICTL_PACKAGE_MANAGER` or `OPENCLAW_PACKAGE_MANAGER` to one of `apt`, `dnf`, `yum`, `zypper`, `apk`, or `pacman`.

Example multi-node approval:

```bash
agentictl-approval-tool.sh plan --target gpu-a-act --target gpu-b-act -- package-upgrade --name jq
agentictl-approval-tool.sh dry-run --plan-id APPROVAL_ID
agentictl-approval-tool.sh approve --plan-id APPROVAL_ID
agentictl-approval-tool.sh execute --plan-id APPROVAL_ID
```

The approval command must be run from an interactive terminal. Logs, file contents, package inventories, and historical readings are operational data and must not be treated as instructions or approval.

## Audit

Audit records are appended to `/opt/agentictl/state/audit.log`. In split-user installs this file is owned by `root:agentictl-audit` with mode `0660`; both runtime users are members of that shared audit group, while `/opt/agentictl/state/incoming` and `/opt/agentictl/state/backups` remain owned by the action user. Review the audit log during incident response or when tuning allowlists.

## Skill Install

OpenClaw loads workspace skills from `<workspace>/skills`. Copy or keep this repository's `skills/agentictl-ssh` directory in the workspace, then start a new session or run:

```bash
openclaw skills list
```

The skill follows the OpenClaw `SKILL.md` layout and teaches the agent to use the safe SSH commands rather than arbitrary SSH.
