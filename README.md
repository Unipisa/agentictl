# agentictl

**Safe SSH verbs for agent-managed Linux nodes.**

`agentictl` gives an AI agent a narrow operational command surface over SSH. It is not a remote shell, not a command passthrough, and not a general automation backdoor. Every exposed command is a declared verb with explicit validation, policy checks, and mode separation.

The first integration target is OpenClaw: this repository includes an OpenClaw skill that teaches an agent how to inspect nodes and preview maintenance actions through `agentictl`.

## Why

AI agents are useful for operations work, but raw SSH is too much authority. `agentictl` sits between the agent and the node:

- The agent can ask for health, logs, service state, and declared maintenance actions.
- The node decides what verbs exist and which targets are allowlisted.
- Mutating actions require `--dry-run` first and explicit `--execute`.
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
ssh node-ro kernel-modules --limit 1000
ssh node-ro fs-list --path /etc --max-depth 1 --limit 50
ssh node-ro log-read --path /var/log/syslog --tail 100
```

Action preview and execution:

```bash
ssh node-act service-restart --unit ollama.service --dry-run
ssh node-act service-restart --unit ollama.service --execute
```

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
bin/agentictl-nodes add --alias prod-gpu-01-ro --host prod-gpu-01-ro --mode readonly
bin/agentictl-nodes role-set --node prod-gpu-01-ro --source user --description "GPU inference node running Ollama"
ssh prod-gpu-01-ro health | bin/agentictl-nodes record --node prod-gpu-01-ro --kind health --source "ssh prod-gpu-01-ro health"
ssh prod-gpu-01-ro package-list --limit 5000 | bin/agentictl-nodes record --node prod-gpu-01-ro --kind packages --source "ssh prod-gpu-01-ro package-list --limit 5000"
```

The skill also includes wrappers under `skills/agentictl-ssh/scripts/` so an agent can use inventory and SSH readings without rebuilding command sequences by hand.

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
