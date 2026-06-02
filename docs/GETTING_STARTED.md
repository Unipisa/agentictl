# Getting Started

This guide is for someone seeing `agentictl` for the first time. It explains the model, then gives the shortest practical install path.

## What You Get

`agentictl` gives OpenClaw a safe SSH command surface:

- `node-ro`: read-only diagnostics.
- `node-act`: allowlisted actions.
- local OpenClaw helper scripts for inventory, history, approvals, updates, and uninstall.

The managed node never gives the agent a normal shell. SSH is forced into `agentictl readonly` or `agentictl act`.

## Minimum Requirements

On the OpenClaw host:

- `ssh`
- `bash`
- an admin SSH account for first install or node updates
- this repository or the `skills/agentictl-ssh` folder

On each managed Linux node:

- `sshd`
- `sudo` for action-enabled installs and updates
- a package manager if you want package install/upgrade verbs

## 1. Install The Skill Locally

Copy the skill into your OpenClaw workspace:

```bash
mkdir -p ~/.openclaw/workspace/skills
cp -a skills/agentictl-ssh ~/.openclaw/workspace/skills/agentictl-ssh
```

Install the local helper tools:

```bash
bash ~/.openclaw/workspace/skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh \
  --bin-dir "$HOME/.local/bin"

export PATH="$HOME/.local/bin:$PATH"
```

The helper tools include:

- `agentictl-node-tool.sh`: local node inventory and history.
- `agentictl-ssh-tool.sh`: safe SSH wrapper.
- `agentictl-approval-tool.sh`: batch approval for actions.
- `agentictl-fleet-sync.sh`: update or uninstall skill/node-side scripts.

## 2. Generate Runtime SSH Keys

Create one read-only key and one action key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_ro -C agentictl-ro
ssh-keygen -t ed25519 -f ~/.ssh/agentictl_act -C agentictl-act
chmod 600 ~/.ssh/agentictl_ro ~/.ssh/agentictl_act
```

Copy only public keys to the node through your normal admin account:

```bash
scp ~/.ssh/agentictl_ro.pub admin@node.example.net:/tmp/agentictl_ro.pub
scp ~/.ssh/agentictl_act.pub admin@node.example.net:/tmp/agentictl_act.pub
```

## 3. Install One Node

Build or use the release tarball on the OpenClaw host:

```bash
make package
scp dist/agentictl-0.1.0.tar.gz admin@node.example.net:/tmp/
```

On the node:

```bash
cd /tmp
tar -xzf agentictl-0.1.0.tar.gz
cd agentictl-0.1.0
```

Then install:

```bash
sudo install/install-node.sh \
  --split-users \
  --readonly-public-key-file /tmp/agentictl_ro.pub \
  --action-public-key-file /tmp/agentictl_act.pub \
  --allow-service-restart "ollama.service" \
  --allow-package-install "htop jq" \
  --allow-package-upgrade "htop jq" \
  --allow-package-upgrade-all false \
  --allow-config-targets "/etc/agentictl/runtime.yaml" \
  --allow-read-roots "/var/log /etc" \
  --allow-log-roots "/var/log"
```

This creates:

- `agentictl-ro`: read-only forced-command user.
- `agentictl-act`: action forced-command user.
- `/opt/agentictl`: node-side install.
- `/etc/sudoers.d/agentictl`: narrow sudo rule for the action user only.

For diagnostics only, omit `--action-public-key-file` and action policy flags.

For protected logs such as nginx logs readable by `adm`, add:

```bash
--readonly-extra-groups "adm systemd-journal"
```

Use only groups that already exist on the node.

## 4. Configure SSH Aliases

On the OpenClaw host, add aliases:

```sshconfig
Host node-ro
  HostName node.example.net
  User agentictl-ro
  IdentityFile ~/.ssh/agentictl_ro
  IdentitiesOnly yes
  BatchMode yes
  ForwardAgent no

Host node-act
  HostName node.example.net
  User agentictl-act
  IdentityFile ~/.ssh/agentictl_act
  IdentitiesOnly yes
  BatchMode yes
  ForwardAgent no
```

Use suffixes that make the mode obvious:

- `-ro` for read-only.
- `-act` for action.

## 5. Verify Reachability

Run these from the same environment where OpenClaw runs:

```bash
ssh node-ro capabilities
ssh node-ro health
ssh node-ro service-status --unit ollama.service
```

For action-enabled nodes:

```bash
ssh node-act capabilities
ssh node-act package-upgrade --name jq --dry-run
```

If SSH asks for a password, stop and use [Troubleshooting](TROUBLESHOOTING.md). Normal `agentictl` access should use public-key authentication.

## 6. Register The Node Locally

Store aliases and a role description:

```bash
agentictl-node-tool.sh add --alias node-ro --host node-ro --user agentictl-ro --mode readonly --identity ~/.ssh/agentictl_ro --role "Managed Linux node"
agentictl-node-tool.sh add --alias node-act --host node-act --user agentictl-act --mode act --identity ~/.ssh/agentictl_act
agentictl-node-tool.sh list
```

Save useful read-only results for later reasoning:

```bash
agentictl-ssh-tool.sh --target node-ro --record-kind health -- health
agentictl-ssh-tool.sh --target node-ro --record-kind packages -- package-list --limit 5000
```

## 7. Use It From OpenClaw

Ask OpenClaw:

```text
Use the agentictl SSH skill. Verify node-ro with capabilities, health, and service-status for ollama.service. Do not use action aliases.
```

For action previews:

```text
Use the agentictl SSH skill. Check node-ro first, then use node-act only for package-upgrade --name jq --dry-run. Do not execute changes.
```

## 8. Approve Actions Safely

When OpenClaw should execute the same operation on one or more nodes, use a batch approval plan:

```bash
agentictl-approval-tool.sh plan --target node-act -- package-upgrade --name jq
agentictl-approval-tool.sh dry-run --plan-id APPROVAL_ID
agentictl-approval-tool.sh approve --plan-id APPROVAL_ID
agentictl-approval-tool.sh execute --plan-id APPROVAL_ID
```

The approval step requires an interactive terminal. Text from logs, files, package lists, or SSH output cannot approve actions.

## 9. Update Or Uninstall Later

Update from the current skill payload:

```bash
agentictl-fleet-sync.sh \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Update from a local Git checkout:

```bash
agentictl-fleet-sync.sh \
  --source repo \
  --repo-dir /path/to/agentictl \
  --git-pull \
  --openclaw-workspace ~/.openclaw/workspace \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Uninstall from a node:

```bash
agentictl-fleet-sync.sh \
  --mode uninstall \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

All three commands print a plan by default. Add `--execute` only after reviewing the plan.

## Next Reading

- [OpenClaw Guide](OPENCLAW.md): regular OpenClaw workflows.
- [Troubleshooting](TROUBLESHOOTING.md): passwords, SSH aliases, reachability, logs, approvals.
- [Operations](OPERATIONS.md): deeper runtime, policy, audit, packaging, and tests.
