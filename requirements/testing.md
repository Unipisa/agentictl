# Testing Requirements

## Default Test

`make test` must run the Docker SSH end-to-end harness.

The harness must use a Docker Compose internal network and must not publish the managed node's SSH port on the host.

## Required Coverage

The Docker test suite must cover:

- Key generation.
- Node installation.
- Read-only-only installation does not create the managed sudoers file.
- Split-user installation grants sudo only to the action user.
- Split-user installation keeps the audit log writable through the shared audit group while keeping staging owned by the action user.
- Split-user installation can add the read-only user to an explicit existing log-reader group and read a protected log without granting read-only sudo.
- Forced-command SSH for read-only mode.
- Package inventory and kernel module inventory in read-only mode.
- Package upgrade inventory in read-only mode.
- Forced-command SSH for action mode.
- Package-install dry-run reports the selected package manager.
- Package-upgrade dry-run reports the selected package manager for named and full upgrades, with policy denial for unallowed packages.
- Package manager override coverage for supported installers in local tests.
- Policy denial.
- Unsafe token denial.
- Dry-run behavior.
- At least one execute path.
- Config staging and config apply.
- Filesystem list/stat/read under allowed roots.
- Log read under allowed log roots.
- Denial of sensitive filesystem paths.
- Inventory add/list, node role persistence, and reading snapshot storage in local tests.
- Bundled skill tool wrappers for inventory operations, SSH recording, batch approval planning, and approved `--execute` gating in local tests.
- Prompt-injection fixture coverage proving hostile remote/stored text cannot authorize `--execute`.
- Batch approval coverage for multi-target plans, non-interactive approval denial, command mismatch denial, and per-target single-use consumption.
- Self-contained skill resource installer and vendored `agentictl-nodes` consistency in local tests.
- Bootstrap instruction generation for adding a node from chat in local tests.
- Skill-vendored node payload manifest and upgrade command generation in local tests.
- Fleet sync plan generation for upgrade and uninstall, including explicit version source, admin identity use, and conservative uninstall flags.

## Local Unit Test

`make unit-test` may run script-level tests directly on Linux or Git Bash. It is secondary to the Docker end-to-end suite.
