# Packaging Requirements

## Node Install

The installer must:

- Create or update the dedicated `agentictl` system user.
- Install binaries under `/opt/agentictl/bin`.
- Install policy under `/opt/agentictl/config/policy.env`.
- Create state directories under `/opt/agentictl/state`.
- Configure forced-command SSH keys.
- Add a narrow sudoers entry for `/opt/agentictl/bin/agentictl-act *`.

## Release Tarball

`make package` must produce:

```text
dist/agentictl-<version>.tar.gz
```

The tarball must include source scripts, docs, requirements, tests, installer, and skill files.

The OpenClaw-side helper `bin/agentictl-nodes` is included in the release tarball but is not installed on managed nodes by `install/install-node.sh`.

## Backward Compatibility

Runtime scripts may retain `OPENCLAW_*` environment-variable fallbacks during early migration, but public docs and new configuration should use `AGENTICTL_*`.
