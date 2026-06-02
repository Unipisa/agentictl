# agentictl

**Safe SSH verbs for agent-managed Linux nodes.**

`agentictl` gives an AI agent a narrow operational command surface over SSH. It is not a remote shell, not a command passthrough, and not a general automation backdoor. Every exposed command is a declared verb with explicit validation, policy checks, and mode separation.

The first integration target is OpenClaw: this repository includes an OpenClaw skill that teaches an agent how to inspect nodes and preview maintenance actions through `agentictl`.

## Why

AI agents are useful for operations work, but raw SSH is too much authority. `agentictl` sits between the agent and the node:

- The agent can ask for health, logs, service state, and declared maintenance actions.
- The node decides what verbs exist and which targets are allowlisted.
- Mutating actions require `--dry-run` first and explicit `--execute`; OpenClaw-side execution uses a local batch approval plan so one approval can cover the same operation across multiple nodes.
- SSH keys are forced to read-only or action mode through `authorized_keys`.

The result is a small, auditable control surface that fits agent workflows without handing the agent an unrestricted shell.

## What It Provides

- `agentictl`: forced-command SSH dispatcher.
- `agentictl-readonly`: diagnostics such as `health`, `service-status`, `journal`, `dmesg`, package inventory, and loaded kernel modules.
- `agentictl-act`: allowlisted actions such as `service-restart`, multi-package-manager `package-install`, and staged config apply.
- `agentictl-nodes`: local inventory and reading snapshot helper for OpenClaw workspaces.
- Bundled OpenClaw skill tools for node inventory and safe SSH readings.
- Node installer for dedicated forced-command SSH users, with optional read-only/action Unix user separation.
- Docker Compose end-to-end test harness with an internal-only network.
- OpenClaw skill: `skills/agentictl-ssh`.
- Markdown requirements for security, packaging, testing, and adding new verbs.

## Example

Read-only diagnostics:

```bash
ssh node-ro health
ssh node-ro service-status --unit ollama.service
ssh node-ro journal --unit ollama.service --since 30m --lines 200
ssh node-ro package-list --limit 2000
ssh node-ro package-upgrades --limit 200
ssh node-ro kernel-modules --limit 1000
ssh node-ro fs-list --path /etc --max-depth 1 --limit 50
ssh node-ro log-read --path /var/log/syslog --tail 100
```

Protected logs remain governed by Unix permissions. For logs such as nginx files readable by `adm`, install with `--readonly-extra-groups "adm systemd-journal"` or use a site-specific log-reader group; `agentictl-ro` still receives no sudo.

Action preview and execution:

```bash
ssh node-act service-restart --unit ollama.service --dry-run
ssh node-act service-restart --unit ollama.service --execute
ssh node-act package-upgrade --name jq --dry-run
```

When OpenClaw drives changes from chat, use the skill's batch approval helper instead of raw `ssh ... --execute`:

```bash
agentictl-approval-tool.sh plan --target node-a-act --target node-b-act -- package-upgrade --name jq
agentictl-approval-tool.sh dry-run --plan-id APPROVAL_ID
agentictl-approval-tool.sh approve --plan-id APPROVAL_ID
agentictl-approval-tool.sh execute --plan-id APPROVAL_ID
```

The approval step requires an interactive terminal and binds the command plus target aliases. Text read from logs, files, SSH output, or saved history is treated as data, not as authorization.

Config changes are staged before apply:

```bash
ssh node-act config-stage --name runtime.yaml --execute < runtime.yaml
ssh node-act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --dry-run
```

## OpenClaw

The included OpenClaw skill explains how an agent should use `agentictl` safely:

```text
skills/agentictl-ssh/SKILL.md
```

For OpenClaw installation, SSH key exchange, node verification, and HEARTBEAT suggestions, start here:

[docs/OPENCLAW.md](docs/OPENCLAW.md)

OpenClaw-side inventory and historical readings are handled by:

```bash
bin/agentictl-nodes list
bin/agentictl-nodes add --alias prod-gpu-01-ro --host prod-gpu-01-ro --user agentictl-ro --mode readonly
bin/agentictl-nodes role-set --node prod-gpu-01-ro --source user --description "GPU inference node running Ollama"
ssh prod-gpu-01-ro health | bin/agentictl-nodes record --node prod-gpu-01-ro --kind health --source "ssh prod-gpu-01-ro health"
ssh prod-gpu-01-ro package-list --limit 5000 | bin/agentictl-nodes record --node prod-gpu-01-ro --kind packages --source "ssh prod-gpu-01-ro package-list --limit 5000"
```

The skill also includes wrappers under `skills/agentictl-ssh/scripts/` so an agent can use inventory and SSH readings without rebuilding command sequences by hand.

The skill is user-invocable in OpenClaw, so it can appear as `/agentictl_ssh`. When installed as a standalone skill folder, run:

```bash
bash skills/agentictl-ssh/resources/install/install-agentictl-skill-tools.sh --bin-dir "$HOME/.local/bin"
```

For adding a node from chat, the skill can generate a minimal terminal bootstrap block with `agentictl-bootstrap-instructions.sh`.

For upgrading an existing node after the skill is updated, the skill includes a checksum-manifested node payload and `agentictl-node-upgrade.sh`. Run skill scripts with `bash` or through the installed helper in `$PATH`, not with `sh`. The upgrade path uses an existing admin SSH account to copy the tarball, rerun the installer, and verify RO/ACT aliases; it does not use `agentictl-act` to upgrade itself.

## Documentation

- [Quickstart](docs/QUICKSTART.md): install, SSH usage, package, and tests.
- [OpenClaw integration](docs/OPENCLAW.md): skill setup, node profiles, verification prompts, HEARTBEAT examples.
- [Operations](docs/OPERATIONS.md): runtime model, policy, audit, and Docker test harness.
- [Requirements](requirements/README.md): project requirements and contribution rules.
- [Adding verbs](requirements/verbs.md): checklist for extending the command surface.

## Status

This project is early-stage and intentionally conservative. New operational verbs should be added slowly, with tests and documented requirements. The default posture is to deny anything that is not explicitly declared.

## Built With AI Assistance

`agentictl` was generated and iterated with help from Codex, OpenAI's AI coding assistant, in collaboration with the project owner. The repository keeps the resulting requirements, tests, and operational documentation in-tree so the design can be reviewed and evolved openly.

## Core Rule

Agents do not get arbitrary SSH. They get declared verbs.
