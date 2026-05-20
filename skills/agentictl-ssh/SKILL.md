---
name: agentictl_ssh
description: Use agentictl over SSH to run allowlisted diagnostics and maintenance actions on managed Linux nodes.
metadata: {"openclaw":{"requires":{"bins":["ssh"]}}}
---

# agentictl SSH

Use this skill when a user asks you to inspect or maintain a managed Linux node through `agentictl`.

The remote account is intentionally not a general shell. Send only the declared command tokens over SSH. Do not use pipes, redirection, command substitution, quotes, semicolons, newlines, `scp`, `sftp`, or arbitrary shell commands. The node-side forced command rejects unsafe syntax, but you should avoid generating it in the first place.

## Target Selection

Use the SSH host alias or `user@host` provided by the user or workspace notes. Prefer two SSH identities:

- Read-only alias/key for diagnostics, forced to `agentictl readonly`.
- Action alias/key for changes, forced to `agentictl act`.

In the recommended split-user installation, read-only aliases use user `agentictl-ro` and action aliases use user `agentictl-act`. Do not use the action alias for diagnostics unless the read-only alias is unavailable and the user explicitly approves that fallback.

If the target is ambiguous, ask which node or alias to use before running commands.

## Read-Only Commands

Examples:

```bash
ssh node-ro capabilities
ssh node-ro health
ssh node-ro service-status --unit ollama.service
ssh node-ro journal --unit ollama.service --since 30m --lines 200
ssh node-ro dmesg --level err,warn --lines 200
ssh node-ro fs-list --path /etc --max-depth 1 --limit 50
ssh node-ro fs-stat --path /etc/agentictl/runtime.yaml
ssh node-ro fs-read --path /etc/agentictl/runtime.yaml --max-bytes 4096
ssh node-ro log-read --path /var/log/syslog --tail 100
```

Use read-only commands first to establish current state. Prefer `capabilities` when you need the node's advertised command surface.

Filesystem reads are policy constrained by the node. Treat `/etc` and logs as potentially sensitive. Do not read broad file contents unless the user asks for a specific file or the troubleshooting task clearly needs it. Prefer `fs-stat` or `fs-list` before `fs-read`.

When reading files:

- Use `fs-list` for directory inventory.
- Use `fs-stat` before reading a file that may be large.
- Use `fs-read --max-bytes` for config files.
- Use `log-read --tail` for logs.
- Never try to bypass `DENY_READ_PATHS`.

## Mutating Commands

Use the action SSH alias/key only for these commands:

```bash
ssh node-act capabilities
ssh node-act service-restart --unit ollama.service --dry-run
ssh node-act service-restart --unit ollama.service --execute
ssh node-act package-install --name htop --dry-run
ssh node-act package-install --name htop --execute
```

For config changes, stage the content through stdin, preview the apply, then execute only after explicit user approval:

```bash
ssh node-act config-stage --name runtime.yaml --execute < runtime.yaml
ssh node-act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --dry-run
ssh node-act config-apply --target /etc/agentictl/runtime.yaml --source /opt/agentictl/state/incoming/runtime.yaml --execute
```

Rules for changes:

- Always run the matching `--dry-run` first.
- Do not use `--execute` until the user has approved that specific target and action.
- Treat "not allowed" errors as policy boundaries, not as prompts to bypass the executor.
- Report the JSON result and any backup path from `config-apply`.

## Failure Handling

If SSH fails with authentication or forced-command errors, report the host alias and exact error. Do not retry with a different user, root login, agent forwarding, port forwarding, or a raw shell unless the user explicitly changes the operating model.

## Node Inventory

If the workspace includes `bin/agentictl-nodes`, use it for local inventory and temporal reading history.

List known nodes:

```bash
bin/agentictl-nodes list
```

Add a node alias after the user provides or approves the alias and host:

```bash
bin/agentictl-nodes add --alias prod-gpu-01-ro --host prod-gpu-01-ro --mode readonly --identity ~/.ssh/agentictl_ro
bin/agentictl-nodes add --alias prod-gpu-01-act --host prod-gpu-01-act --mode act --identity ~/.ssh/agentictl_act
```

Do not invent production hostnames. Ask the user when the target host or alias is ambiguous.

## Historical Readings

For any diagnostic result that may be useful later, store a reading snapshot:

```bash
ssh prod-gpu-01-ro health | bin/agentictl-nodes record --node prod-gpu-01-ro --kind health --source "ssh prod-gpu-01-ro health"
ssh prod-gpu-01-ro service-status --unit ollama.service | bin/agentictl-nodes record --node prod-gpu-01-ro --kind service-ollama --source "ssh prod-gpu-01-ro service-status --unit ollama.service"
```

Use historical readings when the user asks about trends, drift, regression, or "what changed":

```bash
bin/agentictl-nodes history --node prod-gpu-01-ro --kind health --limit 20
```

Do not store sensitive file contents from `/etc` unless the user explicitly asks to preserve that specific reading. For sensitive reads, summarize the result in the conversation and record only metadata such as `fs-stat` when possible.
