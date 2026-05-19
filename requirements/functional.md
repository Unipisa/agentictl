# Functional Requirements

## Modes

`agentictl` exposes two SSH modes:

- `readonly`: diagnostics only. It must not mutate node state.
- `act`: allowlisted actions. Every mutating verb must support `--dry-run` and require explicit `--execute`.

The forced command installed in `authorized_keys` selects the mode:

```text
command="/opt/agentictl/bin/agentictl readonly",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding ...
command="/opt/agentictl/bin/agentictl act",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding ...
```

## Current Verbs

Read-only verbs:

- `capabilities`
- `health`
- `service-status --unit UNIT.service`
- `journal --unit UNIT.service --since 30m --lines 200`
- `dmesg --level err,warn --lines 200`
- `fs-list --path PATH --max-depth N --limit N`
- `fs-stat --path PATH`
- `fs-read --path PATH --tail LINES|--max-bytes BYTES`
- `log-read --path PATH --tail LINES --max-bytes BYTES`

Action verbs:

- `capabilities`
- `service-restart --unit UNIT.service --dry-run|--execute`
- `package-install --name PACKAGE --dry-run|--execute`
- `config-stage --name NAME --dry-run|--execute`
- `config-apply --target PATH --source /opt/agentictl/state/incoming/NAME --dry-run|--execute`

## Output

Machine-readable JSON is required for success and failure paths where practical. Log-streaming diagnostics may emit native command text when that is more useful, but argument validation failures must emit JSON with `ok:false`.

## Policy

Mutating verbs must load `/opt/agentictl/config/policy.env` and enforce allowlists before executing privileged operations.

Filesystem read verbs must also load policy and enforce:

- `ALLOW_READ_ROOTS`
- `ALLOW_LOG_ROOTS`
- `DENY_READ_PATHS`
- `AGENTICTL_MAX_READ_BYTES`
- `AGENTICTL_MAX_LIST_ENTRIES`
- `AGENTICTL_MAX_LIST_DEPTH`

## Local Inventory And Readings

The OpenClaw-side helper `bin/agentictl-nodes` provides:

- `list`: list configured node aliases.
- `add`: add a node alias to the workspace inventory.
- `check`: run basic `capabilities` and `health` checks over SSH.
- `record`: store command output under `state/readings/`.
- `history`: list historical readings for temporal reasoning.

The inventory defaults to `inventory/agentictl-nodes.tsv`. Readings default to `state/readings/YYYY-MM-DD/<node>/`.
