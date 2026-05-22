# agentictl Quickstart

This guide covers local packaging, node installation, basic SSH usage, and tests. For OpenClaw-specific setup, see `OPENCLAW.md`.

## Components

- `bin/agentictl`: forced-command SSH dispatcher. It parses `SSH_ORIGINAL_COMMAND`, rejects unsafe tokens, and routes to the selected mode.
- `bin/agentictl-readonly`: read-only diagnostics for health, logs, kernel messages, service status, package inventory, and loaded kernel modules.
- `bin/agentictl-act`: controlled actions with allowlists, `--dry-run`, explicit `--execute`, multi-package-manager install support, config backups, staging, and audit log.
- `bin/agentictl-nodes`: local OpenClaw-side inventory and reading snapshot helper.
- `install/install-node.sh`: node installer for dedicated forced-command SSH users.
- `skills/agentictl-ssh/SKILL.md`: OpenClaw skill that teaches the agent how to use the safe SSH interface.
- `requirements/`: Markdown requirements and contribution notes for expanding the verb set.

## Install On A Node

Generate read-only and action keys on the agent host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_ro -C agentictl-ro
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_act -C agentictl-act
```

Install on a Linux node:

```bash
sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file ~/.ssh/agentictl_ro.pub \
  --action-public-key-file ~/.ssh/agentictl_act.pub \
  --allow-service-restart "ollama.service agentictl-agent.service" \
  --allow-package-install "htop jq" \
  --allow-config-targets "/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml" \
  --allow-read-roots "/var/log /etc" \
  --allow-log-roots "/var/log"
```

With `--split-users`, the installer creates `agentictl-ro` and `agentictl-act`. Only `agentictl-act` receives a sudoers rule for `/opt/agentictl/bin/agentictl-act *`. The audit log is owned by `root:agentictl-audit` with mode `0660`, so both runtime users can append audit records without making staging directories writable by the read-only user. If you omit `--action-public-key-file`, the installer creates no sudoers entry and removes the managed sudoers file if present.

If read-only diagnostics must read protected service logs, add the read-only user to existing log-reader groups during install:

```bash
# Add this option to the install command when these groups exist on the node:
--readonly-extra-groups "adm systemd-journal"
```

Use only groups that already exist on the node. This is for Unix read permission only; it does not grant sudo to `agentictl-ro`.

Without `--split-users`, the installer keeps the legacy single-user layout with user `agentictl`, but sudoers is still created only when an action public key is installed.

## SSH Usage

Use separate SSH aliases or keys for read-only and action access. Configure aliases in `~/.ssh/config` on the host, user account, or container that runs OpenClaw or any other agent. See `docs/OPENCLAW.md` for copy/paste alias setup.

```bash
ssh node-ro health
ssh node-ro service-status --unit ollama.service
ssh node-ro journal --unit ollama.service --since 30m --lines 200
ssh node-ro package-list --limit 2000
ssh node-ro kernel-modules --limit 1000
ssh node-ro fs-list --path /etc --max-depth 1 --limit 50
ssh node-ro fs-read --path /etc/agentictl/runtime.yaml --max-bytes 4096
ssh node-ro log-read --path /var/log/syslog --tail 100

ssh node-act service-restart --unit ollama.service --dry-run
ssh node-act service-restart --unit ollama.service --execute
```

Config changes are staged through stdin, then applied from the staging directory:

```bash
ssh node-act config-stage --name runtime.yaml --execute < runtime.yaml
ssh node-act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --dry-run
ssh node-act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --execute
```

## Adding Verbs

Verbs are the allowlisted commands an agent can send, such as `health`, `service-status`, or `service-restart`.

Short version:

1. Put read-only verbs in `bin/agentictl-readonly`.
2. Put mutating verbs in `bin/agentictl-act`.
3. Add the verb to the dispatcher allowlist in `bin/agentictl`.
4. Add policy variables for mutating verbs.
5. Add the verb to `capabilities`.
6. Add Docker SSH tests in `tests/docker/scripts/runner.sh`.
7. Update `skills/agentictl-ssh/SKILL.md`.

See `requirements/verbs.md` for the full checklist.

## Inventory And Historical Readings

Add and list OpenClaw-side nodes:

```bash
bin/agentictl-nodes add --alias prod-gpu-01-ro --host prod-gpu-01-ro --user agentictl-ro --mode readonly --identity ~/.ssh/agentictl_ro
bin/agentictl-nodes role-set --node prod-gpu-01-ro --source user --description "GPU inference node running Ollama"
bin/agentictl-nodes list
```

Store a read result for temporal reasoning:

```bash
ssh prod-gpu-01-ro health | bin/agentictl-nodes record --node prod-gpu-01-ro --kind health --source "ssh prod-gpu-01-ro health"
ssh prod-gpu-01-ro package-list --limit 5000 | bin/agentictl-nodes record --node prod-gpu-01-ro --kind packages --source "ssh prod-gpu-01-ro package-list --limit 5000"
ssh prod-gpu-01-ro kernel-modules --limit 2000 | bin/agentictl-nodes record --node prod-gpu-01-ro --kind kernel-modules --source "ssh prod-gpu-01-ro kernel-modules --limit 2000"
bin/agentictl-nodes history --node prod-gpu-01-ro --kind health --limit 10
```

Node roles are stored under `inventory/roles/`. Readings are stored under `state/readings/YYYY-MM-DD/<node>/`.

When using the OpenClaw skill, prefer the bundled wrappers:

```bash
skills/agentictl-ssh/scripts/agentictl-node-tool.sh list
skills/agentictl-ssh/scripts/agentictl-ssh-tool.sh --target prod-gpu-01-ro --record-kind health -- health
```

The skill is `user-invocable`, so OpenClaw can expose `/agentictl_ssh`. If you install only the skill folder, install its local helper tools from bundled resources:

```bash
skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh --bin-dir "$HOME/.local/bin"
```

For a new node, generate the simplest terminal bootstrap commands with:

```bash
skills/agentictl-ssh/scripts/agentictl-bootstrap-instructions.sh --host node.example.net --admin-user admin --role "Managed Linux node"
```

## Package

```bash
make package
```

This creates `dist/agentictl-0.1.0.tar.gz`. Extract it on a node and run `install/install-node.sh`.

## Test

```bash
make test
```

`make test` runs the SSH end-to-end suite in Docker Compose. The Compose network is internal-only: a `runner` container reaches the managed `node` container over Docker DNS, and the node is not published on the host network.

For quick local script checks on a Linux host:

```bash
make unit-test
```

## Design Rules

- Never add arbitrary shell execution or SSH passthrough.
- Keep read-only and mutating capabilities separate.
- Require `--dry-run` before operational approval, and `--execute` before changes.
- Enforce allowlists from `config/policy.env`.
- Back up config targets before replacement.
- Prefer JSON and stable machine-readable output.
