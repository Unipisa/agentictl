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
- `package-list --limit N`
- `package-upgrades --limit N`
- `kernel-modules --limit N`
- `fs-list --path PATH --max-depth N --limit N`
- `fs-stat --path PATH`
- `fs-read --path PATH --tail LINES|--max-bytes BYTES`
- `log-read --path PATH --tail LINES --max-bytes BYTES`

Action verbs:

- `capabilities`
- `service-restart --unit UNIT.service --dry-run|--execute`
- `package-install --name PACKAGE --dry-run|--execute`
- `package-upgrade --name PACKAGE --dry-run|--execute`
- `package-upgrade --all --dry-run|--execute`
- `config-stage --name NAME --dry-run|--execute`
- `config-apply --target PATH --source /opt/agentictl/state/incoming/NAME --dry-run|--execute`

`package-list` must support installed-package inventory from `dpkg-query`, `rpm`, `apk`, and `pacman` databases when available.

`package-install` must support `apt-get`, `dnf`, `yum`, `zypper`, `apk`, and `pacman`. It may auto-detect the package manager or use `AGENTICTL_PACKAGE_MANAGER`/`OPENCLAW_PACKAGE_MANAGER` to select one explicitly. The selected manager must be reported in dry-run and execute JSON output.

`package-upgrades` must list currently known package upgrades from the node's package manager metadata without mutating state. `package-upgrade` must support updating one allowlisted package or all packages when explicitly enabled by policy. The selected manager must be reported in dry-run and execute JSON output.

## Output

Machine-readable JSON is required for success and failure paths where practical. Log-streaming diagnostics may emit native command text when that is more useful, but argument validation failures must emit JSON with `ok:false`.

## Policy

Mutating verbs must load `/opt/agentictl/config/policy.env` and enforce allowlists before executing privileged operations.

Package upgrade actions must use `ALLOW_PACKAGE_UPGRADE` for named package upgrades and `ALLOW_PACKAGE_UPGRADE_ALL=true` for full package-manager upgrades. Full upgrades must be disabled by default.

Filesystem read verbs must also load policy and enforce:

- `ALLOW_READ_ROOTS`
- `ALLOW_LOG_ROOTS`
- `DENY_READ_PATHS`
- `AGENTICTL_MAX_READ_BYTES`
- `AGENTICTL_MAX_LIST_ENTRIES`
- `AGENTICTL_MAX_LIST_DEPTH`

`ALLOW_LOG_ROOTS` defines allowed paths only; Unix file permissions still apply. Installations that need read-only access to protected logs must grant that through explicit existing groups, for example `--readonly-extra-groups "adm systemd-journal"`, not through sudo.

## Local Inventory And Readings

The OpenClaw-side helper `bin/agentictl-nodes` provides:

- `list`: list configured node aliases.
- `add`: add a node alias to the workspace inventory.
- `role-set`: save a local role description for a node.
- `role-show`: return the saved local role description for a node.
- `check`: run basic `capabilities` and `health` checks over SSH.
- `record`: store command output under `state/readings/`.
- `history`: list historical readings for temporal reasoning.

The inventory defaults to `inventory/agentictl-nodes.tsv`. Node role descriptions default to `inventory/roles/<node>.md`. Readings default to `state/readings/YYYY-MM-DD/<node>/`.

When `add` is called without `--user`, the default user must be derived from `--mode`: `agentictl-ro` for `readonly` and `agentictl-act` for `act`. Legacy single-user installs can still be represented by passing `--user agentictl` explicitly.

Software-stack reasoning must use the saved node role, current package inventory, loaded kernel modules, and historical readings before recommending allowlisted package changes.

## Skill Tools

The OpenClaw skill must include bundled script tools for common node operations:

- `agentictl-node-tool.sh`: local wrapper for inventory, role, record, and history operations.
- `agentictl-ssh-tool.sh`: SSH wrapper for declared agentictl verbs with token validation, optional reading recording, and an explicit `--allow-execute` gate for commands containing `--execute`.
- `agentictl-bootstrap-instructions.sh`: generator for minimal copy/paste terminal bootstrap instructions for a new node.
- `agentictl-node-upgrade.sh`: generator/executor for admin-mediated node upgrades using the skill-vendored tarball.

The skill must be `user-invocable: true` so OpenClaw can expose it as `/agentictl_ssh`. Slash invocation must remain model-mediated unless a dedicated typed OpenClaw tool is implemented; it must not dispatch raw user input directly to `exec`.

The skill must include self-contained resources for installing local helper scripts when only the skill folder is installed:

- `resources/bin/agentictl-nodes`
- `resources/dist/agentictl-<version>.tar.gz`
- `resources/dist/agentictl-<version>.manifest`
- `resources/install/install-agentictl-skill-tools.sh`
- `resources/node/install-node.sh`

The skill instructions should prefer these tools when available and document raw SSH as the fallback path.

When the user asks to add or install a node, the skill should first produce concise terminal commands, asking only for missing host, admin user, and role. Bootstrap instructions must use the admin account only for initial installation and then switch to `agentictl-ro`/`agentictl-act` runtime aliases.

When the user asks to upgrade a node, the skill should prefer the vendored tarball and `agentictl-node-upgrade.sh`. Upgrade execution must use an existing admin SSH account, verify the tarball checksum, rerun the node installer, and then verify read-only and action aliases. Do not use `agentictl-act` to replace or upgrade the agentictl installation itself.
