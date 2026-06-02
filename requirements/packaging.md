# Packaging Requirements

## Node Install

The installer must:

- Create or update dedicated SSH users.
- Support the legacy single-user layout with user `agentictl`.
- Support `--split-users`, defaulting to `agentictl-ro` and `agentictl-act`.
- Support `--readonly-extra-groups` for adding the read-only runtime user to existing Unix groups such as `adm` or `systemd-journal` without granting sudo.
- Install binaries under `/opt/agentictl/bin`.
- Install policy under `/opt/agentictl/config/policy.env`.
- Include `AGENTICTL_PACKAGE_MANAGER=auto` in newly generated policy files.
- Include package-upgrade policy keys in newly generated policy files and append missing upgrade policy keys during updates without overwriting existing policy values.
- Create state directories under `/opt/agentictl/state`.
- Configure forced-command SSH keys.
- Add a narrow sudoers entry for `/opt/agentictl/bin/agentictl-act *` only when an action public key is installed.
- Remove the managed sudoers file when installing a read-only-only node.
- Support uninstalling managed SSH access, sudoers, and installed binaries.
- Require explicit uninstall flags before deleting runtime users or the base directory containing state/config.
- In split-user mode, grant sudo only to the action user.
- In split-user mode, create a shared audit group, default `agentictl-audit`, for append access to `/opt/agentictl/state/audit.log`.
- Keep staging and backup directories owned by the action user when an action key is installed.

## Release Tarball

`make package` must produce:

```text
dist/agentictl-<version>.tar.gz
```

The tarball must include source scripts, docs, requirements, tests, installer, and skill files.

The OpenClaw-side helper `bin/agentictl-nodes`, bundled skill scripts under `skills/agentictl-ssh/scripts/`, and self-contained skill resources under `skills/agentictl-ssh/resources/` are included in the release tarball but are not installed on managed nodes by `install/install-node.sh`.

The OpenClaw skill resources must include a node payload tarball, checksum manifest, and a copy of the node installer so updating the skill also provides the payload needed to upgrade managed nodes from the OpenClaw host.

The skill installer must install fleet lifecycle helpers, including the helper that syncs OpenClaw-side skill resources and upgrades or uninstalls node-side agentictl using the bundled payload.

## Backward Compatibility

Runtime scripts may retain `OPENCLAW_*` environment-variable fallbacks during early migration, but public docs and new configuration should use `AGENTICTL_*`.
