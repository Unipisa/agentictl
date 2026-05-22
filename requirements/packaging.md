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
- Create state directories under `/opt/agentictl/state`.
- Configure forced-command SSH keys.
- Add a narrow sudoers entry for `/opt/agentictl/bin/agentictl-act *` only when an action public key is installed.
- Remove the managed sudoers file when installing a read-only-only node.
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

## Backward Compatibility

Runtime scripts may retain `OPENCLAW_*` environment-variable fallbacks during early migration, but public docs and new configuration should use `AGENTICTL_*`.
