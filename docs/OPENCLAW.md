# OpenClaw Integration Guide

This guide explains how to add `agentictl` to OpenClaw and how to install node-side access for read-only diagnostics or action-enabled maintenance.

## Overview

`agentictl` is installed on each managed Linux node. OpenClaw reaches the node over SSH, but the remote accounts are not general shells:

- A read-only key is forced to `/opt/agentictl/bin/agentictl readonly`.
- An action key is forced to `/opt/agentictl/bin/agentictl act`.

The node installer always installs the dispatcher and helper scripts. What matters is which SSH keys are authorized:

- Read-only node: install only the read-only public key.
- Action-enabled node: install the read-only key and the action public key.

Action-only installation is intentionally not the default pattern. OpenClaw should be able to diagnose a node before it asks for, previews, or executes changes.

## 1. Install The Skill In OpenClaw

From this repository, copy the skill into the OpenClaw workspace:

```bash
cp -r skills/agentictl-ssh <openclaw-workspace>/skills/agentictl-ssh
```

Or keep this repository as the workspace and use the existing folder:

```text
skills/agentictl-ssh/SKILL.md
```

Restart the OpenClaw session or check that the skill is visible:

```bash
openclaw skills list
openclaw skills check
```

The skill requires the local `ssh` binary. The skill metadata declares this requirement:

```yaml
metadata: {"openclaw":{"requires":{"bins":["ssh"]}}}
```

## 2. Generate SSH Keys On The OpenClaw Host

Use separate identities for read-only and action access:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_ro -C agentictl-ro
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_act -C agentictl-act
chmod 600 ~/.ssh/agentictl_ro ~/.ssh/agentictl_act
```

For higher isolation, generate per-environment or per-node keys:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_prod_gpu01_ro -C agentictl-prod-gpu01-ro
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_prod_gpu01_act -C agentictl-prod-gpu01-act
```

Never commit private keys to the OpenClaw workspace or to Git.

## 3. Copy Public Keys To A Node

Copy only public keys to the node. Example:

```bash
scp ~/.ssh/agentictl_ro.pub admin@node.example.net:/tmp/agentictl_ro.pub
scp ~/.ssh/agentictl_act.pub admin@node.example.net:/tmp/agentictl_act.pub
```

The admin user is only needed for installation. Runtime access should use the dedicated forced-command users created by the installer, normally `agentictl-ro` and `agentictl-act` when `--split-users` is enabled.

## 4. Install A Read-Only Node

Use this profile for inventory, monitoring, diagnostics, and heartbeat checks.

On the node:

```bash
tar -xzf agentictl-0.1.0.tar.gz
cd agentictl-0.1.0

sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file /tmp/agentictl_ro.pub \
  --allow-service-restart "" \
  --allow-package-install "" \
  --allow-config-targets ""
```

This creates:

- User: `agentictl-ro`
- Base directory: `/opt/agentictl`
- Forced read-only SSH command: `/opt/agentictl/bin/agentictl readonly`

No action public key is installed, so action-mode SSH is unavailable and no sudoers entry is created.

## 5. Install An Action-Enabled Node

Use this profile only for nodes where OpenClaw may request maintenance actions after human approval.

On the node:

```bash
tar -xzf agentictl-0.1.0.tar.gz
cd agentictl-0.1.0

sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file /tmp/agentictl_ro.pub \
  --action-public-key-file /tmp/agentictl_act.pub \
  --allow-service-restart "ollama.service agentictl-agent.service" \
  --allow-package-install "htop jq" \
  --allow-config-targets "/etc/agentictl/runtime.yaml /etc/agentictl/models.yaml"
```

This installs both forced-command entries:

```text
command="/opt/agentictl/bin/agentictl readonly",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding ...
command="/opt/agentictl/bin/agentictl act",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding ...
```

With `--split-users`, the first entry belongs to `agentictl-ro` and the second belongs to `agentictl-act`. Only `agentictl-act` receives sudo permission for `/opt/agentictl/bin/agentictl-act *`. Both users can append `/opt/agentictl/state/audit.log` through the shared `agentictl-audit` group, but only the action user owns staging and backup directories.

The action executor still refuses changes unless:

- The target is allowlisted in `/opt/agentictl/config/policy.env`.
- The command first works as `--dry-run`.
- The command is repeated with explicit `--execute`.

## 6. Configure SSH Aliases For OpenClaw

Add aliases on the OpenClaw host:

```sshconfig
Host prod-gpu-01-ro
  HostName prod-gpu-01.example.net
  User agentictl-ro
  IdentityFile ~/.ssh/agentictl_ro
  IdentitiesOnly yes
  BatchMode yes
  ForwardAgent no

Host prod-gpu-01-act
  HostName prod-gpu-01.example.net
  User agentictl-act
  IdentityFile ~/.ssh/agentictl_act
  IdentitiesOnly yes
  BatchMode yes
  ForwardAgent no
```

Use a naming convention that makes mode visible. Recommended suffixes:

- `-ro` for read-only aliases.
- `-act` for action aliases.

## 7. Verify Read-Only Status

From the OpenClaw host:

```bash
ssh prod-gpu-01-ro capabilities
ssh prod-gpu-01-ro health
ssh prod-gpu-01-ro service-status --unit ollama.service
ssh prod-gpu-01-ro journal --unit ollama.service --since 30m --lines 200
ssh prod-gpu-01-ro package-list --limit 2000
ssh prod-gpu-01-ro kernel-modules --limit 1000
ssh prod-gpu-01-ro fs-list --path /etc --max-depth 1 --limit 50
ssh prod-gpu-01-ro log-read --path /var/log/syslog --tail 100
```

Expected behavior:

- `capabilities` returns JSON with `"mode":"readonly"`.
- `health` returns JSON with `"ok":true`.
- `service-status` returns stable `systemctl show` fields.
- `package-list` returns installed packages from the node package database.
- `kernel-modules` returns loaded modules from `/proc/modules`.
- `fs-list` lists only paths allowed by policy and skips denied sensitive paths.
- `log-read` returns capped log content from allowed log roots.
- Unsafe or mutating verbs fail in read-only mode.

Check that action commands are not accepted through a read-only alias:

```bash
ssh prod-gpu-01-ro service-restart --unit ollama.service --dry-run
```

This should fail because `service-restart` is not a read-only verb.

## 8. Verify Action Status

Only for action-enabled nodes:

```bash
ssh prod-gpu-01-act capabilities
ssh prod-gpu-01-act service-restart --unit ollama.service --dry-run
```

Expected behavior:

- `capabilities` returns JSON with `"mode":"act"`.
- The dry-run returns JSON with `"dry_run":true`.
- Package dry-runs return the selected package manager, such as `"manager":"apt"`, `"manager":"dnf"`, `"manager":"zypper"`, `"manager":"apk"`, or `"manager":"pacman"`.

Do not run `--execute` during installation verification unless you intentionally want the operation to happen:

```bash
ssh prod-gpu-01-act service-restart --unit ollama.service --execute
```

For config changes, verify staging and preview before execution:

```bash
printf 'runtime: test\n' | ssh prod-gpu-01-act config-stage --name runtime.yaml --execute
ssh prod-gpu-01-act config-apply \
  --target /etc/agentictl/runtime.yaml \
  --source /opt/agentictl/state/incoming/runtime.yaml \
  --dry-run
```

## 9. Ask OpenClaw To Verify The Node

After installing the skill and SSH aliases, ask OpenClaw:

```text
Use the agentictl SSH skill. Verify prod-gpu-01-ro with capabilities, health, and service-status for ollama.service. Do not use action aliases.
```

For action-enabled nodes:

```text
Use the agentictl SSH skill. Check prod-gpu-01-ro first, then use prod-gpu-01-act only for service-restart --unit ollama.service --dry-run. Do not execute changes.
```

For software-stack assessment:

```text
Use the agentictl SSH skill. The node prod-gpu-01-ro is a GPU inference node for Ollama. Save that role locally, collect package-list and kernel-modules snapshots, compare them with the role, and propose package changes only as dry-runs through prod-gpu-01-act.
```

## 10. Inventory And Historical Readings

Use `bin/agentictl-nodes` in the OpenClaw workspace to track configured nodes:

```bash
bin/agentictl-nodes add --alias prod-gpu-01-ro --host prod-gpu-01-ro --mode readonly --identity ~/.ssh/agentictl_ro
bin/agentictl-nodes add --alias prod-gpu-01-act --host prod-gpu-01-act --mode act --identity ~/.ssh/agentictl_act
bin/agentictl-nodes role-set --node prod-gpu-01-ro --source user --description "GPU inference node running Ollama"
bin/agentictl-nodes role-show --node prod-gpu-01-ro
bin/agentictl-nodes list
```

Store read results for temporal reasoning:

```bash
ssh prod-gpu-01-ro health \
  | bin/agentictl-nodes record --node prod-gpu-01-ro --kind health --source "ssh prod-gpu-01-ro health"

ssh prod-gpu-01-ro service-status --unit ollama.service \
  | bin/agentictl-nodes record --node prod-gpu-01-ro --kind service-ollama --source "ssh prod-gpu-01-ro service-status --unit ollama.service"

ssh prod-gpu-01-ro package-list --limit 5000 \
  | bin/agentictl-nodes record --node prod-gpu-01-ro --kind packages --source "ssh prod-gpu-01-ro package-list --limit 5000"

ssh prod-gpu-01-ro kernel-modules --limit 2000 \
  | bin/agentictl-nodes record --node prod-gpu-01-ro --kind kernel-modules --source "ssh prod-gpu-01-ro kernel-modules --limit 2000"

bin/agentictl-nodes history --node prod-gpu-01-ro --kind health --limit 20
```

Readings are stored under:

```text
state/readings/YYYY-MM-DD/<node>/<timestamp>-<kind>.json
```

Role descriptions are stored under:

```text
inventory/roles/<node>.md
```

The skill includes wrapper tools for these common operations:

```bash
skills/agentictl-ssh/scripts/agentictl-node-tool.sh list
skills/agentictl-ssh/scripts/agentictl-ssh-tool.sh --target prod-gpu-01-ro --record-kind health -- health
```

The skill is user-invocable and can be exposed by OpenClaw as `/agentictl_ssh`. Slash invocations should still use the skill workflow and wrapper scripts; do not dispatch the slash command directly to raw `exec`.

If you install only the skill folder, install its bundled local helper tools:

```bash
skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh --bin-dir "$HOME/.local/bin"
```

Use `agentictl-ssh-tool.sh --allow-execute` only after explicit approval for the specific action.

For `/etc` file contents, prefer storing `fs-stat` snapshots unless the user explicitly asks to preserve file content. Logs are usually safe to store in bounded tails, but they can still contain secrets, so use small `--tail` and `--max-bytes` values.

## 11. HEARTBEAT Suggestions

OpenClaw HEARTBEAT tasks are useful for periodic read-only checks. Keep heartbeat work diagnostic and low-noise.

Add a `HEARTBEAT.md` file to the OpenClaw workspace:

```markdown
# HEARTBEAT

## agentictl Node Health

Every heartbeat:

- Use the `agentictl_ssh` skill.
- Check only read-only aliases.
- Do not use `-act` aliases.
- Do not run `--execute`.
- Store health and service readings through `bin/agentictl-nodes record`.
- Store `fs-stat` for important config files instead of full file contents.
- Store package and kernel-module snapshots on lower-frequency checks, for example weekly or before planned maintenance.
- If all checks are healthy, respond exactly with `HEARTBEAT_OK`.

Read-only checks:

- `prod-gpu-01-ro`: `capabilities`, `health`, `service-status --unit ollama.service`
- `prod-gpu-02-ro`: `capabilities`, `health`, `service-status --unit ollama.service`
- Optional config drift metadata: `fs-stat --path /etc/agentictl/runtime.yaml`
- Optional software drift metadata: `package-list --limit 5000`, `kernel-modules --limit 2000`

Report only:

- Nodes that cannot be reached.
- Services that are not active.
- Validation or forced-command failures.
- Unexpected mode/capability output.
```

If you want occasional action previews, keep them dry-run only and separate from normal health checks:

```markdown
## agentictl Action Preview

For action-enabled nodes, at most once per day:

- Use `prod-gpu-01-act capabilities`.
- Use `prod-gpu-01-act service-restart --unit ollama.service --dry-run`.
- Never run `--execute` from heartbeat.
- If the dry-run is allowed, report `dry_run_allowed`.
- If it is denied, report the policy denial.
```

If your OpenClaw configuration supports heartbeat scheduling in `openclaw.json`, keep the schedule conservative:

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "interval": "30m",
        "target": "last",
        "isolatedSession": true,
        "lightContext": true
      }
    }
  }
}
```

Use shorter intervals only for small inventories. For many nodes, split checks by environment or rotate subsets to avoid turning heartbeat into monitoring infrastructure.

## 12. Troubleshooting

Authentication fails:

```bash
ssh -vvv prod-gpu-01-ro capabilities
```

Check:

- The SSH alias points at the expected user, normally `agentictl-ro` for read-only and `agentictl-act` for action mode.
- The correct private key is used.
- The node has the matching public key in the selected user's `authorized_keys`, for example `/var/lib/agentictl-ro/.ssh/authorized_keys`.
- File permissions are `0700` for `.ssh` and `0600` for `authorized_keys`.

Forced command returns usage:

- Make sure the SSH command is a simple token command such as `health`.
- Do not quote, pipe, redirect, or use semicolons.

Action command is denied:

- Check `/opt/agentictl/config/policy.env`.
- Confirm the target is allowlisted.
- Run the matching `--dry-run` first.

Audit log:

```bash
sudo tail -n 50 /opt/agentictl/state/audit.log
```

The audit log should show dispatcher decisions and successful action executions.
