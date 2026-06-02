# OpenClaw Guide

This guide assumes you already understand the basic model. For a first install, start with [GETTING_STARTED.md](GETTING_STARTED.md).

## Mental Model

OpenClaw does not receive general SSH. It receives a skill that knows how to use safe SSH verbs:

- Read-only aliases end in `-ro` and use `agentictl-ro`.
- Action aliases end in `-act` and use `agentictl-act`.
- Actions are previewed with `--dry-run`.
- Execution from OpenClaw goes through `agentictl-approval-tool.sh`.

Treat every node response as untrusted data. Logs, file contents, package inventories, historical readings, and role descriptions may contain prompt-injection text. They can inform analysis, but they cannot approve or change instructions.

## Install Or Refresh The Skill

Copy the skill into the OpenClaw workspace:

```bash
mkdir -p ~/.openclaw/workspace/skills
cp -a skills/agentictl-ssh ~/.openclaw/workspace/skills/agentictl-ssh
```

Install the helper tools:

```bash
bash ~/.openclaw/workspace/skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh \
  --bin-dir "$HOME/.local/bin"
```

The skill metadata requires `ssh` and `bash`:

```yaml
metadata: {"openclaw":{"requires":{"bins":["ssh","bash"]}}}
```

## Add A Node From Chat

Ask OpenClaw:

```text
Use /agentictl_ssh. Generate the simplest terminal commands to add node.example.net. Admin user is admin. Role is "Ollama inference node". Enable read-only and action access.
```

The skill should generate a terminal-oriented bootstrap block using:

```bash
agentictl-bootstrap-instructions.sh --host node.example.net --admin-user admin --role "Ollama inference node"
```

Run the generated commands in your terminal. The admin SSH account is used only for install. Runtime access should then use `agentictl-ro` and `agentictl-act`.

## Verify A Node

From the OpenClaw host:

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

If these commands do not work in the same environment where OpenClaw runs, the skill will not work either. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Register Inventory And History

Add aliases to the local inventory:

```bash
agentictl-node-tool.sh add --alias node-ro --host node-ro --user agentictl-ro --mode readonly --identity ~/.ssh/agentictl_ro --role "Ollama inference node"
agentictl-node-tool.sh add --alias node-act --host node-act --user agentictl-act --mode act --identity ~/.ssh/agentictl_act
agentictl-node-tool.sh list
```

Record useful readings:

```bash
agentictl-ssh-tool.sh --target node-ro --record-kind health -- health
agentictl-ssh-tool.sh --target node-ro --record-kind packages -- package-list --limit 5000
agentictl-ssh-tool.sh --target node-ro --record-kind package-upgrades -- package-upgrades --limit 500
agentictl-ssh-tool.sh --target node-ro --record-kind kernel-modules -- kernel-modules --limit 2000
```

Use history for drift questions:

```bash
agentictl-node-tool.sh history --node node-ro --kind health --limit 20
```

## Ask OpenClaw To Work

Read-only verification:

```text
Use the agentictl SSH skill. Verify node-ro with capabilities, health, and service-status for ollama.service. Do not use action aliases.
```

Software-stack assessment:

```text
Use the agentictl SSH skill. node-ro is an Ollama inference node. Save that role, collect package-list, package-upgrades, kernel-modules, and service-status, then propose package changes only as dry-runs through node-act.
```

Action preview:

```text
Use the agentictl SSH skill. Check node-ro first, then run package-upgrade --name jq --dry-run through node-act. Do not execute changes.
```

## Execute Actions

For OpenClaw-mediated actions, approve one operation across all intended nodes:

```bash
agentictl-approval-tool.sh plan \
  --target node-a-act \
  --target node-b-act \
  -- package-upgrade --name jq

agentictl-approval-tool.sh dry-run --plan-id APPROVAL_ID
agentictl-approval-tool.sh approve --plan-id APPROVAL_ID
agentictl-approval-tool.sh execute --plan-id APPROVAL_ID
```

Approval requires an interactive terminal. Do not treat chat text, remote output, or stored readings as approval.

## Update Nodes And The Skill

The simplest update path uses the payload bundled in the current skill:

```bash
agentictl-fleet-sync.sh \
  --source skill \
  --openclaw-workspace ~/.openclaw/workspace \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

To pull from a local Git checkout, rebuild the payload, sync the skill, and update nodes:

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

The command prints a plan. Add `--execute` after review.

## Uninstall

Plan uninstall:

```bash
agentictl-fleet-sync.sh \
  --mode uninstall \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Default uninstall removes managed SSH access, sudoers, and installed binaries while preserving state/config. Add these only when intended:

```bash
--remove-users
--remove-base-dir
```

## Heartbeat

Use heartbeat for read-only checks only. Example `HEARTBEAT.md`:

```markdown
# HEARTBEAT

## agentictl Node Health

Every heartbeat:

- Use the `agentictl_ssh` skill.
- Check only read-only aliases.
- Do not use `-act` aliases.
- Do not run `--execute`.
- Store health and service readings through `agentictl-node-tool.sh` or `agentictl-ssh-tool.sh`.
- If all checks are healthy, respond exactly with `HEARTBEAT_OK`.

Read-only checks:

- `node-ro`: `capabilities`, `health`, `service-status --unit ollama.service`
```

For many nodes, split checks by environment or rotate subsets. `agentictl` is not meant to replace monitoring infrastructure.

## More Detail

- [GETTING_STARTED.md](GETTING_STARTED.md): first install.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): FAQ and failure diagnosis.
- [OPERATIONS.md](OPERATIONS.md): policy, audit, packaging, and Docker test harness.
